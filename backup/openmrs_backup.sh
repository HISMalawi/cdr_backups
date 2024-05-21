#!/bin/sh

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



user_name=$(whoami)
backup_folder="/home/$user_name/backup"
echo "Checking for OpenMRS dumps older than 3 days in $backup_folder"
##############################################################
#Delete OpenMRS dumps older than 3 days                      #
##############################################################
find "$backup_folder" -type f -name "openmrs_*gz" -mtime +3 -exec rm {} \;




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
   echo "SUCCESS : $db configured in \"/var/www/EMR-API/config/database.yml\"... "
fi

#############################################################
# Check if database.yml is present. If not, do not proceed   #
#############################################################

if [ ! -f /var/www/EMR-API/config/database.yml ]; then
	  echo "ERROR: File database.yml not found. Consult HIS Officer."
	    exit
    else
	      echo "SUCCESS: File database.yml found. Checking for database.yml file."
fi

############################################################
# Extracting username and password from database.yml        #
############################################################

username=$(awk '/^[[:blank:]]*username:[[:blank:]]*/{sub(/^[[:blank:]]*username:[[:blank:]]*/, ""); print; exit}' /var/www/EMR-API/config/database.yml)
password=$(awk '/^[[:blank:]]*username:[[:blank:]]*/{getline; if ($1 ~ /^[[:blank:]]*password:[[:blank:]]*$/) {print $2; exit}}' /var/www/EMR-API/config/database.yml)

if [ -z "$username" ] || [ -z "$password" ]; then
	  echo "ERROR: Username or password not found in /var/www/EMR-API/config/database.yml. Process exiting."
	    exit 1
    else
	      echo "SUCCESS: Username and password configured in /var/www/EMR-API/config/database.yml."
fi

# Use the "$username" and "$password" variables as needed for further operations.

name=$(mysql -u$username -p$password $db -se "select concat(location_id,'_',replace(replace(replace(lower(name),' ','_'),')',''),'(','')) name from $db.location l where location_id in (select property_value from $db.global_property gp where lower(property)='current_health_center_id')")

mysqldump --routines -u$username -p$password $db | gzip -c > ~/backup/openmrs_${name}_$(date +%d-%m-%Y).sql.gz 

rm database_yaml_values.txt
echo done





