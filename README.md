CDR BACKUPS INSTALLATION

Pre-requisites;
1) EMR
2) MySQL 8+
3) Server running on Ubuntu or any Debian distribution

Steps to deploy;
1) clone the repository and copy the folders on the home directory of the ubuntu user
2) add the following cronjobs ;
   
   ## CronJob for generation of OpenMRS backup
   00 18 * * * cd ~/backup/ && bash openmrs_backup.sh >> ~/backup/logs/openmrs_backup.log 2>&1

   ## CronJob for generation of RDS delta
   00 17 * * * cd ~/cdr_rds_dump/  && bash rds_dump.sh 5 >> ~/cdr_rds_dump/logs/rds_delta.log 2>&1
    
