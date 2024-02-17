#!/usr/bin/bash
#
# Flush current file data
#
flush_data_and_metrics ()
{
   if [ "x${RESULT_FORMAT}" == "x" ] || [ "x${RESULT_FORMAT}" == "xdefault" ]
   then
      tio_avg=$( bc <<< "scale=2; ${wio_avg}+${rio_avg}" )
      tbw_avg=$( bc <<< "scale=2; ${wbw_avg}+${rbw_avg}" )
      printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "${g_storage_clustername}" ${g_storage_pvc} ${g_storage_type} "${g_storage_environment}" ${jb_jobname} ${mode} ${jb_bs} ${g_numjobs} ${jb_iodepth} ${client_number} $( bc <<< "scale=2; ${wbw_avg}/1024") $( bc <<< "scale=2; ${wio_avg}/1.00") $( bc <<< "scale=2; ${wlat_mean}/1000000") $( bc <<< "scale=2; ${wlat_95th}/1000000") $( bc <<< "scale=2; ${rbw_avg}/1024") $( bc <<< "scale=2; ${rio_avg}/1.00") $( bc <<< "scale=2; ${rlat_mean}/1000000") $( bc <<< "scale=2; ${rlat_95th}/1000000") $( bc <<< "scale=2; ${tbw_avg}/1024") $( bc <<< "scale=2; ${tio_avg}/1.00") ${jb_runtime} >>./results.csv
   else
      echo "Detailed metrics format is not yet available"
   fi
}
#
# Default and simplified header
#
create_default_header ()
{
   echo "Generating default header"
   echo "Cluster Name,PVC,Storage Type,Environment,Test Name,IO Mode,IO Size,Jobs,Depth,Client,write MiB/s,Writes/s,Mean Write Latency (ms),95th Write Latency,read MiB/s,Reads/s,Mean Read Latency (ms),95th Read Latency,Total MiB/s,Total IOPS,Total Time (s)" >./results.csv
}
#
# Detailed header
#
create_detailed_header ()
{
   echo "Detailed header"
   echo "Cluster Name,PVC,Storage Type,Environmen,name,ioengine,direct,numjobs,size,mode,iosize,iodepth,totalios,runtime,rbw_avg,riops_avg,rbw_min,rbw_max,rbw_mean,rbw_std,riops_min,riops_max,riops_mean,riops_std,rlat_min_ms,rlat_max_ms,rlat_mean,rlat_std_ms,wbw_avg,wiops_avg,wbw_min,wbw_max,wbw_mean,wbw_std,wiops_min,wiops_max,wiops_mean,wiops_std,wlat_min_ms,wlat_max_ms,wlat_mean,wlat_std_ms" >./results.csv
}
#
# Extract global info
#
get_global_info ()
{
   input_file=$1
   export g_ioengine=$(cat ${input_file} | jq -r '."global options".ioengine')
   export g_direct=$(cat ${input_file} | jq -r '."global options".direct')
   export g_numjobs=$(cat ${input_file} | jq -r '."global options".numjobs')
   export g_size=$(cat ${input_file} | jq -r '."global options".size')
   export g_storage_pvc=fio-pv-claim	# This is not really variable and set directly in the yaml
   export g_storage_type=$(egrep -e '^storage_type' ${tool_directory}/config.file | cut -f2 -d= | sed -e 's/"//g')
   export g_storage_clustername=$(egrep -e '^cluster_name' ${tool_directory}/config.file | cut -f2 -d= | sed -e 's/"//g')
   export g_storage_environment=$(egrep -e '^cluster_environment' ${tool_directory}/config.file | cut -f2 -d= | sed -e 's/"//g')
}
#
# Extract job info
#
get_job_info ()
{
   input_file=$1
   export jb_jobname=$(cat ${input_file} | jq -r '.client_stats[0].jobname')
   export jb_mode=$(cat ${input_file} | jq -r '.client_stats[0]."job options".rw')
   export jb_bs=$(cat ${input_file} | jq -r '.client_stats[0]."job options".bs')
   export jb_iodepth=$(cat ${input_file} | jq -r '.client_stats[0]."job options".iodepth')
   export jb_runtime=$(cat ${input_file} | jq -r '.client_stats[0]."job options".runtime')
}
#
# Extract latency metrics
#
get_lat_metrics ()
{
   input_buffer="$1"
   lat_min=$(echo ${input_buffer} | jq -r '.lat_ns.min')
   lat_max=$(echo ${input_buffer} | jq -r '.lat_ns.max')
   lat_mean=$(echo ${input_buffer} | jq -r '.lat_ns.mean')
   lat_dev=$(echo ${input_buffer} | jq -r '.lat_ns.stddev')
   if [ "x{client_number}" == "xSUM" ]
   then
      #
      # If multi client total entry no percentiels are displayed
      #
      lat_95th='N/A'
   else
      lat_95th=$(echo ${input_buffer} | jq -r '.clat_ns.percentile."95.000000"')
      if [[ "x${lat_95th}" == "xnull" ]]
      then
         lat_95th=0.0
      fi
   fi
   printf 'Latency %s,%s,%f,%f,%s\n' ${lat_min} ${lat_max} ${lat_mean} ${lat_dev} ${lat_95th}
   if [ "x$2" == "xr" ]
   then
      export rlat_avg=${lat_avg}
      export rlat_min=${lat_min}
      export rlat_max=${lat_max}
      export rlat_mean=${lat_mean}
      export rlat_dev=${lat_dev}
      export rlat_95th=${lat_95th}
   elif [ "x$2" == "xw" ]
   then
      export wlat_avg=${lat_avg}
      export wlat_min=${lat_min}
      export wlat_max=${lat_max}
      export wlat_mean=${lat_mean}
      export wlat_dev=${lat_dev}
      export wlat_95th=${lat_95th}
   else
      echo "ERROR: Missing or invalid get_lat_metrics argument"
      exit
   fi
}
#
# Extract IOPS metrics
#
get_io_metrics ()
{
   input_buffer="$1"
   io_avg=$(echo ${input_buffer} | jq -r '.iops')
   io_min=$(echo ${input_buffer} | jq -r '.iops_min')
   io_max=$(echo ${input_buffer} | jq -r '.iops_max')
   io_mean=$(echo ${input_buffer} | jq -r '.iops_mean')
   io_dev=$(echo ${input_buffer} | jq -r '.iops_stddev')
   printf 'IOPS %s,%s,%s,%f,%f\n' ${io_avg} ${io_min} ${io_max} ${io_mean} ${io_dev}
   if [ "x$2" == "xr" ]
   then
      export rio_avg=${io_avg}
      export rio_min=${io_min}
      export rio_max=${io_max}
      export rio_mean=${io_mean}
      export rio_dev=${io_dev}
   elif [ "x$2" == "xw" ]
   then
      export wio_avg=${io_avg}
      export wio_min=${io_min}
      export wio_max=${io_max}
      export wio_mean=${io_mean}
      export wio_dev=${io_dev}
   else
      echo "ERROR: Missing or invalid get_io_metrics argument"
      exit
   fi
}
#
# Extract badnwidth metrics
#
get_bw_metrics ()
{
   input_buffer="$1"
   bw_avg=$(echo ${input_buffer} | jq -r '.bw')
   bw_min=$(echo ${input_buffer} | jq -r '.bw_min')
   bw_max=$(echo ${input_buffer} | jq -r '.bw_max')
   bw_mean=$(echo ${input_buffer} | jq -r '.bw_mean')
   bw_dev=$(echo ${input_buffer} | jq -r '.bw_dev')
   printf 'Bandwidth %s,%s,%s,%f,%f\n' ${bw_avg} ${bw_min} ${bw_max} ${bw_mean} ${bw_dev}
   if [ "x$2" == "xr" ]
   then
      export rbw_avg=${bw_avg}
      export rbw_min=${bw_min}
      export rbw_max=${bw_max}
      export rbw_mean=${bw_mean}
      export rbw_dev=${bw_dev}
   elif [ "x$2" == "xw" ]
   then
      export wbw_avg=${bw_avg}
      export wbw_min=${bw_min}
      export wbw_max=${bw_max}
      export wbw_mean=${bw_mean}
      export wbw_dev=${bw_dev}
   else
      echo "ERROR: Missing or invalid get_bw_metrics argument"
      exit
   fi
}
#
# Extract read activity metrics
#
get_read_metrics ()
{
   input_file=$1
   index=$2
   get_bw_metrics "$(cat ${input_file} | jq -r ".client_stats[${index}].read")" "r"
   get_io_metrics "$(cat ${input_file} | jq -r ".client_stats[${index}].read")" "r"
   get_lat_metrics "$(cat ${input_file} | jq -r ".client_stats[${index}].read")" "r"
}
#
# Extract write activity metrics
#
get_write_metrics ()
{
   input_file=$1
   index=$2
   get_bw_metrics "$(cat ${input_file} | jq -r ".client_stats[${index}].write")" "w"
   get_io_metrics "$(cat ${input_file} | jq -r ".client_stats[${index}].write")" "w"
   get_lat_metrics "$(cat ${input_file} | jq -r ".client_stats[${index}].write")" "w"
}
#
# Extract the list of all tests stored in the server
#
tool_directory=$(pwd)
mkdir -p ~/simple-fio-results
for file in $(oc rsh fio-storage ls -tr /mnt)
do
   #
   # File naming example: fio_8k_randwrite_sample1_24_02_14_19_14.tar
   #
   filetr=$(echo ${file} | sed -e 's/\r//g')
   if [ "x${filetr}" == "xprefill_output.log" ]
   then
      echo "Skipping ${file}"
      continue
   fi
   echo "Processing ${file}"
   set +x
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
   target_dir="./fio-${year}${month}${day}-${hour}${minute}"
   cd ~/simple-fio-results
   rm -Rf ./fio
   rm -Rf ${target_dir}
   output=$(tar -xvf ${filetr} fio/summary.log)
   mv ./fio ${target_dir}
   #
   # Now that the fio summary.log file is extracted, collect the metrics
   #
   if ! test -f ./results.csv
   then
      if [ "x${RESULT_FORMAT}" == "x" ] || [ "x${RESULT_FORMAT}" == "xdefault" ]
      then
         create_default_header
      else   
         create_detailed_header
      fi
   fi
   cat ${target_dir}/summary.log | egrep -v -e "^<fio-server" | egrep -v -e "^fio: " >${target_dir}/summary.out
   multi_client=$(cat ${target_dir}/summary.out | jq '.client_stats[].jobname' | wc -l)
   if [ "x${multi_client}" != "x1" ]
   then 
      job_entries=$( bc <<< ${multi_client}-1 )
      get_global_info ${target_dir}/summary.out
      get_job_info ${target_dir}/summary.out
      index=0
      while [ "x${index}" != "x${job_entries}" ]
      do
         echo "Processing client number ${index} for ${target_dir}"
         export client_number=${index}
         get_write_metrics ${target_dir}/summary.out ${index}
         get_read_metrics ${target_dir}/summary.out ${index}
         #
         # Print metrics to results.csv
         #
         flush_data_and_metrics
         index=$( bc <<< ${index}+1 )
      done
      export client_number='SUM'
      get_write_metrics ${target_dir}/summary.out ${index}
      get_read_metrics ${target_dir}/summary.out ${index}
      flush_data_and_metrics
   else
      export client_number='Single'
      get_global_info ${target_dir}/summary.out
      get_job_info ${target_dir}/summary.out
      get_write_metrics ${target_dir}/summary.out 0
      get_read_metrics ${target_dir}/summary.out 0
      #
      # Print metrics to results.csv
      #
      flush_data_and_metrics
      #
      # Remove the current file and its directory
      #
      #rm -Rf ${target_dir}
   fi
done
