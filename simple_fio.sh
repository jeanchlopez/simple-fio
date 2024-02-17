#!/bin/bash
#
# Detect CPU architecture
#
arch=$(lscpu | grep Architecture | awk '{print $2}')
if [ "x${arch}" == "xs390x" ]
then
	export container_image="$(grep base_container_image config.file | awk -F "=" '{print $2}')-${arch}"
else
	export container_image="$(grep base_container_image config.file | awk -F "=" '{print $2}')"
fi
echo "Will be using container image as ${container_image}"
#
#==========================================================
# Creating and setting up the namespace
#----------------------------------------------------------
namespace="simple-fio"
if [ `oc get project | grep ${namespace} | awk '{print $1}'` ]
then 
	oc project ${namespace} > /dev/null
else
	echo "Creating project simple-fio"
	oc create namespace ${namespace}
	oc project ${namespace}

fi

#============================
# Check fio storage pod is up
#----------------------------
if [[ $(oc get pvc | grep fio-data-pvc | awk '{print $1}') != "fio-data-pvc" ]];
        then
        oc create -f fio-data-pvc.yaml
fi
if [[ $(oc get pods | grep fio-storage | awk '{print $1}') != "fio-storage" ]];
        then
        oc apply -f fio-storage.yaml
fi

#=========================================================
# Creating the fio job file from config
#---------------------------------------------------------
pfile=prefill.fio
prefill=`grep "^prefill" config.file | awk -F "=" '{print $2}'`
iter=1
bs_range=()
for bs in $(grep ^bs config.file | awk -F "=" '{print $2}'); 
do
bs_range+=($bs)
done
for blocksize in ${bs_range[@]}; 
do

	file=job${iter}.fio
	echo "[global]" > ${file}
	echo "ioengine=libaio" >> ${file}
	grep "^direct" config.file >> ${file}
	grep "^numjobs" config.file >> ${file}
	grep "^size" config.file >> ${file}

	if [ `grep "^storage_type" config.file | awk -F "=" '{print $2}'` == "ocs-storagecluster-ceph-rbd" ]; then
		echo "filename=/dev/rbd" >> ${file}
	elif [ `grep "^storage_type" config.file | awk -F "=" '{print $2}'` == "ocs-storagecluster-cephfs" ]; then
		echo "directory=/mnt/pvc" >> ${file}
		prefill=false
	else
		echo "Job file not configured properly as storage_type in config file is unknown"
	fi

	echo "" >> ${file}

	if [[ $prefill == "true" ]]; then
		cp ${file} ${pfile}
		echo -e "[fio_test] \ntime_based=0 \nrw=write \nbs=128K \niodepth=1 \ngroup_reporting" >> ${pfile}
	fi


	echo -e "[fio_test]" >> ${file}
	grep "^rw" config.file >> ${file}
	echo "bs=${blocksize}" >> ${file}
	grep "^time_based" config.file >> ${file}
	grep "^runtime" config.file >> ${file}
	grep "^iodepth" config.file >> ${file}
	#
	# Changed ^rw to ^rw= to make sure we ignore rwmixread= and rwmixwrite= if specified
	# Made same change to client.yaml
	# Update the if to be immune to null variables
	#
	job=$(grep "^rw=" config.file | awk -F "=" '{print $2}')
        echo "Set job = ${job}"
	# Additional FIO parameters based on job/workload
	# For write workload, the parameters have been imported from Benchmark Operator
	# For random workloads, the parameters have been imported from ODF QE CI job file
	#--------------------------------------------------------------------------------
	if [ "x${job}" == "xwrite" ]
	then
                echo "Setting parameters for Sequential Write"
        	echo "fsync_on_close=1" >> ${file}
        	echo "create_on_open=1" >> ${file}
	elif [ "x${job}" == "xreadwrite" ]
	then
                echo "Setting parameters for Sequential Read/Write"
        	echo "fsync_on_close=1" >> ${file}
        	echo "create_on_open=1" >> ${file}
        	#echo "rwmixread=70" >> ${file}
	elif [[ $job =~ ^[rand*] ]]
	then
                echo "Setting parameters for Random IOs: ${job}"
        	echo "randrepeat=0" >> ${file}
        	echo "allrandrepeat=0" >> ${file}
	fi
        cat ${file}
	#-------------------------------------------------------------------------------
	grep "^log_avg_msec" config.file >> ${file}
	echo -e "write_iops_log=iops" >> ${file}
	echo -e "write_lat_log=latency" >> ${file}
	echo "group_reporting" >> ${file}
	iter=$(($iter+1))
done
#
#==========================================================
# Create fio server and client pods
#----------------------------------------------------------
server=`grep "^server" config.file | awk -F "=" '{print $2}'`
sample=`grep "^sample" config.file | awk -F "=" '{print $2}'`
storage=`grep "^storage(Gi)" config.file | awk -F "=" '{print $2}'`
fio_args_prefill=""
fio_args_job=""
num_of_bs=${#bs_range[@]}

export sample=${sample}
export storage=${storage}
export prefill=${prefill}
export num_of_bs=${num_of_bs}

job_info=job_info.txt
> $job_info
echo "prefill=${prefill}" >> $job_info
echo "num_of_bs=${num_of_bs}" >> $job_info
echo "sample=${sample}" >> $job_info
echo "server=${server}" >> $job_info

server_ip=server_ip.txt
> $server_ip

for ((i=0;i<$server;i++));
do
	export srv=${i}
	if [ `grep "^storage_type" config.file | awk -F "=" '{print $2}'` == "ocs-storagecluster-ceph-rbd" ]; then
		envsubst < blk-pvc.yaml | oc create -f -
		sleep 20
		envsubst < blk-server.yaml | oc create -f -
	elif [ `grep "^storage_type" config.file | awk -F "=" '{print $2}'` == "ocs-storagecluster-cephfs" ]; then
		envsubst < fs-pvc.yaml | oc create -f -
	sleep 20
		envsubst < fs-server.yaml | oc create -f -
	fi
	oc wait pod --for=condition=Ready -l app=fio-server --timeout=1h > /dev/null
	pod=`echo fio-server${i}`

	serverIP=`oc get pod ${pod} -n ${namespace} --template '{{.status.podIP}}'`
	echo $serverIP >> $server_ip
done

sleep 10
#
# Allow support for json output to be parsed by print_results.sh
#
if [ "x${1}" == "xjson2csv" ]
then
	echo "Will be using JSON formatted output from fio"
	sed -e "s#image: to_be_updated_at_run_time#image: ${container_image}#g" client-json2csv.yaml >client-gen.yaml
else
	sed -e "s#image: to_be_updated_at_run_time#image: ${container_image}#g" client.yaml >client-gen.yaml
fi
#
# Check we do not have any client pod running
#
client_pod=$(oc get po -n ${namespace} -o name | grep "fio-client")
if [ "x${client_pod}" != "x" ]
then
   #
   # We do so let's remove that pod so we can recreate it
   #
   oc delete -n ${namespace} ${client_pod}
fi
oc create -f client-gen.yaml
oc wait pod --for=condition=Ready -l app=fio-client --timeout=1h > /dev/null

oc cp ${job_info} ${namespace}/fio-client:/tmp
oc cp ${pfile} ${namespace}/fio-client:/tmp
oc cp ${server_ip} ${namespace}/fio-client:/tmp 

for iter in $(seq 1 $num_of_bs)
do
	oc cp job${iter}.fio ${namespace}/fio-client:/tmp
done

#---------------
# End of script
#---------------
