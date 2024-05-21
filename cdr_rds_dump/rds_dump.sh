#!/bin/bash
#
#
#################################################################################################################################################################
#START OF SCRIPT : rds_dump.sh                                                                                                                                  #
#################################################################################################################################################################
#
#
#
#
#########################
#variable declarations  #
#########################
#
#
#

db_file="./rds_table_structure.csv"
sql_separator=","
program_id="01"
tables=($(awk -F ',' '{print $1}' $db_file | uniq))
q="'"
re='^[0-9]+$'
dt=$(date '+%d/%m/%Y');
declare -a meta_tables=("program_workflow_state" "pharmacies")            #These are tables where we are getting all the data. No date to be used as criteria

############################################################
# Extracting username and password from database.yml        #
############################################################

db_user=$(awk '/^[[:blank:]]*username:[[:blank:]]*/{sub(/^[[:blank:]]*username:[[:blank:]]*/, ""); print; exit}' /var/www/EMR-API/config/database.yml)
db_pwd=$(awk '/^[[:blank:]]*username:[[:blank:]]*/{getline; if ($1 ~ /^[[:blank:]]*password:[[:blank:]]*$/) {print $2; exit}}' /var/www/EMR-API/config/database.yml)

if [ -z "$db_user" ] || [ -z "$db_pwd" ]; then
          echo "ERROR: Username or password not found in /var/www/EMR-API/config/database.yml. Process exiting."
            exit 1
    else
              echo "SUCCESS: Username and password configured in /var/www/EMR-API/config/database.yml."
fi


##################################
#function to capture real time   #
##################################
#
#
timestamp() {
  date +"%T" # current time
}

###############################################################
# Define the file path where the service files for EMR are   ##
###############################################################
file_path="/etc/systemd/system/emr-api.service"

#############################################################################################################
# Use grep to find the line containing 'ExecStart' and '-e', then use awk to extract the string after '-e' ##
#############################################################################################################

emr_mode=$(grep 'ExecStart=.*-e' "$file_path" | awk -F '-e ' '{print $2}' | awk '{print $1}')

if [ -z "$emr_mode" ]; then
   echo "EMR Mode Not Set. Exiting"
   exit 1
else
    echo "EMR Mode is $emr_mode"

fi

########################
# Output the result   ##
########################
echo "EMR Mode: $emr_mode"


##############################################################################
#check if script has been run with correct arguments. exit if not like that  #
##############################################################################
#
#

if  ! [[ $1 =~ $re ]] ; then
 echo "ERROR!!! : RUN THE SCRIPT WITH CORRECT ARGUMENT!!! CONSULT DATA LAKE TEAM FOR ASSISTANCE!!! " >&2;
 exit 1
else
 echo "STARTING RDS GENERATION SCRIPT"
fi

####################################################################################
#check if metadata file : rds_table_structure.csv is present. exit if not present  #
####################################################################################
#
#
if [ ! -f $db_file ]; then
    echo "ERROR : File $db_file not found. Consult DataLake Team "
    exit 1
else
    echo "SUCCESS : File $db_file found . Checking for database.yml file "
fi

#############################################################
#check if database.yml is present. If not, do not proceed   #
#############################################################
#
#
if [ ! -f /var/www/EMR-API/config/database.yml ]; then
    echo "ERROR : File database.yml not found. Consult HIS Officer "
    exit
else
    echo "SUCCESS : File database.yml found . Checking for database.yml file "
fi

################################################################################################
#check if last dump generated date file is present. If not present, create 1 with current date #
################################################################################################
#
#
if [ ! -f .last_gen_date.txt ]; then
    lsd=$(date '+%Y-%m-%d')
    echo "'${lsd}'" > .last_gen_date.txt 
else
    echo "SUCCESS : Last generation date file found"
fi

#######################################################################
#function to use to parse database.yml and get values for development #
#######################################################################
#
#
function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=%s\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

#######################
#parsing database.yml #
#######################
#
#
parse_yaml /var/www/EMR-API/config/database.yml > database_yaml_values.txt


##################################################################################################
# Read the database_yaml_values.txt file and extract the database name based on the emr_mode    ##
##################################################################################################

db=$(grep "^${emr_mode}_database=" database_yaml_values.txt | cut -d '=' -f 2)

# Check if db is empty (no match found in databases.txt)
if [ -z "$db" ]; then
    echo "No database found for $emr_mode mode"
    exit 1
else
    echo "Database for $emr_mode mode is $db"
fi


#####################################################################################
#Checking if configured database is present for development. If not present, exit   #
#####################################################################################
#
#
if [[ "$db" == "" ]]; then

   echo "ERROR : No database configured for development in \"/var/www/EMR-API/config/database.yml\".. Process exiting.."
   exit 1
else
   echo "SUCCESS : $db configured in \"/var/www/EMR-API/config/database.yml\"... Checking if MySQL service is running "
fi

#################################################################
#checking if mysql is running. Exit if it is not running        #
#################################################################
#
#
UP=$(pgrep mysql | wc -l);
if [ "$UP" -eq 0 ];
then
        echo "ERROR : MySQL is down. Report to HIS Officer ";
        exit 1

else
        echo "SUCCESS : MySQL Service is running... Checking if configured database exists ";
fi

################################################################
#declaring array containing all present databases in MySQL     #
################################################################
#
#
existing_schemas=($(mysql -u$db_user -p$db_pwd -se "select s.SCHEMA_NAME from information_schema.SCHEMATA s"))

#########################################################################################
#checking if configured database if present in the database array. If not present, exit #
#########################################################################################
#
#

if [[ "${existing_schemas[@]}" =~ "${db}" ]]; then
   echo "SUCCESS : Configured database : $db exists. Initiating rds routine"
else 
   echo "ERROR : Configured database : $db does not exist. Consult HIS Officer"
   exit 1
fi

######################################################
#getting site_id from and facility_name database     #
######################################################
#
#
pre_facility_id=$(mysql -D$db -u$db_user -p$db_pwd -se "select property_value from global_property where property='current_health_center_id'" 2>&1 | grep -v "Warning")
facility_id=$(printf "%05d" $pre_facility_id)
facility_name=$(mysql -D$db -u$db_user -p$db_pwd -se "select replace(replace(replace(replace(lower(l.name),' ','_'),'(',''),')',''),'\'','') from location l join global_property gp on l.location_id=gp.property_value where gp.property='current_health_center_id'" 2>&1 | grep -v "Warning")

########################################################
#removing windows imprint on rds_table_structure.csv   #
########################################################
#
#

sed -i 's/\r//g' $db_file

############################################
#determine dump generation start date      #
############################################
#
#
if [ "$1" -eq 0 ]                                                                   #for getting full dump, argument = 0
  then 
    start_date="'0000-00-00'"   
    declare -a dwildcard=("date_created")                                           #date column to use
    declare -a dwildcard2=("date_created")                                          #date column to use for drug_order
    dump_file_name="rds_${facility_name}_dump.sql"                                  #naming convention for full dump
else                                                                                #for getting delta, argument is a number greater than 1
   lgd=$(cat .last_gen_date.txt)       #check last generated date file
   pre_start_date=$(mysql -D$db -u$db_user -p$db_pwd -se "select case when date_sub(date(now()),interval $1 day) > $lgd then $lgd else date_sub(date(now()),interval $1 day) end sdate")
   start_date="'${pre_start_date}'"    #start date to use when generating delta
   declare -a dwildcard=("date_created" "date_voided" "date_changed" "date_retired") #date columns to use
   declare -a dwildcard2=("date_created" "date_voided")                              #date columns to use for drug_order
   dump_file_name="rds_${facility_name}_`date '+%Y_%m_%d'`.sql"                      #naming convention for delta
fi

#####################################
#starting dump generation process   #
#####################################
#
#

echo "[Starting RDS dump generation process for : $facility_name]"                   

#########################################
#append sql statement to dump file      #
#########################################
#
#

echo "SET foreign_key_checks = 0;" >> $dump_file_name

###########################################
#Loop through tables in rds_structure.csv #
###########################################
#
#
for table in "${tables[@]}"
do
sql="select "
sql_d="select "
r_columns="("
printf "\n"
echo "[Initializing process for table : $table]"
printf "\n"

##########################################################################################
#generating concatenations for data preparation by looping through table structure file  #
#preparing sql statements to use when creating temporary tables                          #
##########################################################################################
#
#
while IFS=, read -r col1 col2 col3
 do
 if [[ $col1 == "$table" ]];    then
   if [ $col3 -eq 0 ];   then
            concat_value=${col2}
            testv=${col3}
            sql+=" ${table}.${concat_value} ${sql_separator} "
            sql_d+=" ${table}.${concat_value}${sql_separator} "
            r_columns+="${table}.${concat_value}${sql_separator} "
   else
            concat_value=${col2}
            sql+=" case when ${table}.${concat_value} is null then null else cast(concat(${table}.${concat_value}${sql_separator}${q}${program_id}${q}${sql_separator}${q}${facility_id}${q}) as unsigned integer) end ${concat_value}${sql_separator} "
            sql_d+=" ${table}.${concat_value}${sql_separator} "
            r_columns+="${table}.${concat_value}${sql_separator} "
     fi
  else
       continue
  fi   
done <  $db_file                                      #file to use 
 create_sql="create table temp_$table as "            #prefix to use when creating temporary table
 sql_final="  ${create_sql} ${sql::-2} "              #removing unnecessary comma
 sql_d="${sql_d::-2}"                                 #removing unnecessary comma
 r_columns="${r_columns::-2})"                        #removing unnecessary comma

#######################################################################################################################################
#Completing create statements and running logic for date column dependent table except drug_order which relies on a join with orders  #
#######################################################################################################################################
#
#
  while IFS=, read -r col1 col2 col3
  do
   if [[ "$col1" == "$table" ]]; then
     if [[ "$table" != "drug_order" ]] && ! [[ "${meta_tables[@]}" =~ "$table" ]]; then
      for date_wildcard in "${dwildcard[@]}"
      do
      if [[ "$col2" == "$date_wildcard" ]]; then
       limit_value=50000
       determinant=1
       offset_value=0
   
        while [ $determinant -eq 1 ] 
         do
           trailing_sql=" from ${table} where date(${table}.${col2}) >= ${start_date} limit ${limit_value} offset ${offset_value}"
           running_query=" ${sql_final} ${trailing_sql}"
           display_query="\"${sql_d} ${trailing_sql}\""
           echo "[$dt $(timestamp)] : [processing batch for ($display_query)]"
           mysql -D$db -u$db_user -p$db_pwd -e "set global sql_mode = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'" 2>&1 | grep -v "Warning"
           mysql -D$db -u$db_user -p$db_pwd -e "drop table if exists temp_$table" 2>&1 | grep -v "Warning"
           mysql -D$db -u$db_user -p$db_pwd -e "$running_query" 2>&1 | grep -v "Warning"
           mysqldump -u$db_user -p$db_pwd --replace --skip-add-drop-table --no-create-db --no-create-info $db temp_$table >> $facility_name.sql 2>&1 | grep -v "Warning"
           r_string="\`temp_${table}\`"
           grep REPLACE $facility_name.sql >> temp_$dump_file_name
           rm $facility_name.sql
           sed -i "s/REPLACE INTO ${r_string}/REPLACE INTO ${table} ${r_columns} /" temp_$dump_file_name
           cat temp_$dump_file_name >> $dump_file_name
           rm temp_$dump_file_name
           mysql -D$db -u$db_user -p$db_pwd -e "drop table temp_$table" 2>&1 | grep -v "Warning"
           offset_value=$(( $offset_value + $limit_value ))
           determinant=$(mysql -D$db -u$db_user -p$db_pwd -se "SELECT IFNULL( (SELECT 1  FROM $table where date(${table}.$col2) > $start_date  LIMIT 1 offset $offset_value) ,'0')" 2>&1 | grep -v "Warning")       
          done
       else 
          continue
       fi
       done
#########################################################################################################################################
#Completing create statements and running logic for date column independent table except drug_order which relies on a join with orders  #
#########################################################################################################################################
#
#
#
      elif   [[ "$table" != "drug_order" ]] && [[ "${meta_tables[@]}" =~ "$table" ]]; then

        limit_value=50000
        determinant=1
        offset_value=0
        while [ $determinant -eq 1 ]
         do
           trailing_sql=" from $table limit ${limit_value} offset ${offset_value} "
           running_query=" ${sql_final} ${trailing_sql}"
           display_query="\"${sql_d} ${trailing_sql}\""
           echo "[$dt $(timestamp)] : [processing batch for ($display_query)]"
           mysql -D$db -u$db_user -p$db_pwd -e "set global sql_mode = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'" 2>&1 | grep -v "Warning"
           mysql -D$db -u$db_user -p$db_pwd -e "drop table if exists temp_$table" 2>&1 | grep -v "Warning"
           mysql -D$db -u$db_user -p$db_pwd -e "$running_query" 2>&1 | grep -v "Warning"
           mysqldump -u$db_user -p$db_pwd --replace --skip-add-drop-table --no-create-db --no-create-info $db temp_$table >> $facility_name.sql 2>&1 | grep -v "Warning"
           r_string="\`temp_${table}\`"
           grep REPLACE $facility_name.sql >> temp_$dump_file_name
           rm $facility_name.sql
           sed -i "s/REPLACE INTO ${r_string}/REPLACE INTO ${table} ${r_columns} /" temp_$dump_file_name
           cat temp_$dump_file_name >> $dump_file_name
           rm temp_$dump_file_name
           mysql -D$db -u$db_user -p$db_pwd -e "drop table if exists temp_$table" 2>&1 | grep -v "Warning"
           offset_value=$(( $offset_value + $limit_value ))
           determinant=$(mysql -D$db -u$db_user -p$db_pwd -se "SELECT IFNULL( (SELECT 1  FROM $table LIMIT 1 offset $offset_value) ,'0')" 2>&1 | grep -v "Warning")
        done
      break
##########################################################################################################
#Completing create statements and running logic for table drug_order which relies on a join with orders  #
##########################################################################################################
#
#

      elif [[ "$table" == "drug_order" ]] && ! [[ "${meta_tables[@]}" =~ "$table" ]]; then
      for date_wild in "${dwildcard2[@]}"
      do
    
        limit_value=50000
        determinant=1
        offset_value=0
        while [ $determinant -eq 1 ]
         do
           trailing_sql=" from $table join orders on $table.order_id = orders.order_id where date(orders.${date_wild}) >= $start_date limit ${limit_value} offset ${offset_value} "           
           running_query=" ${sql_final} ${trailing_sql}"
           display_query="\"${sql_d} ${trailing_sql}\""
           echo "[$dt $(timestamp)] : [processing batch for ($display_query)]"
           mysql -D$db -u$db_user -p$db_pwd -e "set global sql_mode = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'" 2>&1 | grep -v "Warning"
           mysql -D$db -u$db_user -p$db_pwd -e "drop table if exists temp_$table" 2>&1 | grep -v "Warning"
           mysql -D$db -u$db_user -p$db_pwd -e "$running_query" 2>&1 | grep -v "Warning"
           mysqldump -u$db_user -p$db_pwd --replace --skip-add-drop-table --no-create-db --no-create-info $db temp_$table >> $facility_name.sql 2>&1 | grep -v "Warning"
           r_string="\`temp_${table}\`"
           grep REPLACE $facility_name.sql >> temp_$dump_file_name
           rm $facility_name.sql
           sed -i "s/REPLACE INTO ${r_string}/REPLACE INTO ${table} ${r_columns} /" temp_$dump_file_name
           cat temp_$dump_file_name >> $dump_file_name
           rm temp_$dump_file_name
           mysql -D$db -u$db_user -p$db_pwd -e "drop table if exists temp_$table" 2>&1 | grep -v "Warning"
           offset_value=$(( $offset_value + $limit_value ))
           determinant=$(mysql -D$db -u$db_user -p$db_pwd -se "SELECT IFNULL( (SELECT 1  FROM $table join orders on $table.order_id = orders.order_id where date(orders.${date_wild}) >= $start_date  LIMIT 1 offset $offset_value) ,'0')" 2>&1 | grep -v "Warning")
          done
        done
         break
      fi
   else
        continue
   fi
 done <  $db_file

done
#########################################################
#compressing dump file  and sending staging directory   #
#########################################################
#
#
gzip $dump_file_name
mv -f ./*.gz /var/www/EMR-API/log/
#####################################
#updating last generation date file #
#####################################
#
#
lsd_f=$(date '+%Y-%m-%d')
echo "'${lsd_f}'" > .last_gen_date.txt
rm database_yaml_values.txt
#############################################################################################################################################################
#END OF SCRIPT                                                                                                                                              #
#############################################################################################################################################################
