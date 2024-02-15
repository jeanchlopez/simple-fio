#!/bin/bash
#
# Extract the list of all tests stored in the server
#
mkdir -p ~/simple-fio-results
for file in $(oc rsh fio-storage ls -tr /mnt | grep -v prefill)
do
   #
   # File naming example: fio_8k_randwrite_sample1_24_02_14_19_14.tar
   #
   filetr=$(echo ${file} | sed -e 's/\r//g')
   echo "Processing ${file}"
   bs=$(echo ${file} | cut -d_ -f2)
   mode=$(echo ${file} | cut -d_ -f3)
   sample=$(echo ${file} | cut -d_ -f4 | sed 's/sample//')
   year="20$(echo ${file} | cut -d_ -f5)"
   month="$(echo ${file} | cut -d_ -f6)"
   day="$(echo ${file} | cut -d_ -f7)"
   hour="$(echo ${file} | cut -d_ -f8)"
   minute="$(echo ${file} | cut -d_ -f9 | cut -d. -f1)"
   echo "FIO Completed on ${year}-${month}-${day} at ${hour}:${minute}"
   echo "- Sample    : ${sample}"
   echo "- Block size: ${bs}"
   echo "- IO mode   : ${mode}"
   #
   # Extracting file for processing
   #
   oc cp fio-storage:/mnt/${filetr} ~/simple-fio-results/${filetr}
done
