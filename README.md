# simple-fio
As the name suggests, this is a simplified implementation of fio to be executed in a Kubernetes/Openshift environment without any bells and whistles of Elastic search, Grafana or any framework integration. 

This can be used to quickly run some fio tests in a Kubernetes/Openshift environment without any extra configuration. 

## How to run
1. git clone https://github.com/bose-abhishek/simple-fio.git
2. cd simple-fio/
3. Edit config file and set the appropriate parameters required. Described in detail in the next section.
4. sh simple_fio.sh
5. Once the test is over, execute the delete script (sh delete_simple_fio.sh) to delete the test setup (fio server and client pods).
6. To delete the project, execute the nuke script. This will delete the namespace, fio storage along with all the stored data (sh nuke_simple-fio.sh). 

## Test Configuration
To execute a fio test, one needs to only change the parameters in the config.file.
There are three sections in the config.file:
1. Tool Paramaters
   - cluster_name: Give a name to the cluster so it can be printed in the results generated
   - cluster_environment: Provide context fopr your test environment

NOTE: The fio output format has been changed so it can be parsed through `print_results.sh`. If you with to go back to the old
format, edit the `client.yaml` file and remove the `--output-format=json` option on line 56.

2. OCS Parameters
   - storage_type: This defines the undelying storage class to be used.
     * options: ocs-storagecluster-ceph-rbd | ocs-storagecluster-cephfs

3. FIO Execution Parameters
   - server: Number of fio server pods (usually this equals to the number of ODF workers or multiples of it). FIO test is actually executed on it, RBD volumes or CephFS mounts are present in these pods.
   - sample: Number of iterations of the test
   - prefill: To perform prefill or not for RBD volumes
     * options: true | false
   - storage(Gi): size of each PVC (should be larger than 'numjob x fio volume/file size')

4. FIO parameters: These parameters are used exactly as defined in the [FIO documentation](https://fio.readthedocs.io/en/latest/fio_doc.html)
   - [direct](https://fio.readthedocs.io/en/latest/fio_doc.html#cmdoption-arg-direct): If value is true, use non-buffered I/O. This is usually O_DIRECT.
   - [rw](https://fio.readthedocs.io/en/latest/fio_doc.html#cmdoption-arg-readwrite): Type of I/O pattern.
     * rw=read | write | randread | randwrite | randrw
   - [bs](https://fio.readthedocs.io/en/latest/fio_doc.html#block-size): The block size in bytes used for I/O units. Unlike fio, here multiple block sizes can be mentioned with space separated.
     * bs=8k 16k
   - [numjobs](https://fio.readthedocs.io/en/latest/fio_doc.html#cmdoption-arg-numjobs): Create the specified number of clones of this job. Each clone of job is spawned as an independent thread or process.
   - [time_based](https://fio.readthedocs.io/en/latest/fio_doc.html#cmdoption-arg-time-based): If set, fio will run for the duration of the runtime specified even if the file(s) are completely read or written. 
     * time_based=0 | 1
   - [runtime](https://fio.readthedocs.io/en/latest/fio_doc.html#cmdoption-arg-runtime): Limit runtime. The test will run until it completes the configured I/O workload or until it has run for this specified amount of time, whichever occurs first. The value is interpreted in seconds.
   - [size](https://fio.readthedocs.io/en/latest/fio_doc.html#cmdoption-arg-size): File or block size.
   - [iodepth](https://fio.readthedocs.io/en/latest/fio_doc.html#cmdoption-arg-iodepth): Number of I/O units to keep in flight against the file
   - [log_avg_msec](https://fio.readthedocs.io/en/latest/fio_doc.html#cmdoption-arg-log-avg-msec): Setting this option makes fio average the each log entry over the specified period of time, reducing the resolution of the log. This defines the granularity of the fio logs and can be changed according to test requirements. As a rule of thumb, it can be set as:
      * log_avg_msec=5000 # 5 seconds for 5/10 minute jobs
      * log_avg_msec=1000 # 10 seconds for more than 10 minute jobs

* Apart from the above mentioned fio parameters, few of the parameters are automatically set in the fio job file depending on the workload type.
    * When `rw` is set as `write`, `fsync_on_close=1` and `create_on_open=1` is applied.
    * When `rw` is set as any random workload, `randrepeat=0` and `allrandrepeat=0` is applied.
  
## Check output

### All clients average results 
```
$ oc logs fio-client -f
Initializing and Configuring FIO jobs
*********Prefill**************
All clients: (groupid=0, jobs=3): err= 0: pid=0: Tue Nov 21 11:13:16 2023
  write: IOPS=968, BW=121Mi (127M)(60.0GiB/507636msec); 0 zone resets
    slat (usec): min=3, max=3010, avg=79.17, stdev=89.26
    clat (usec): min=3059, max=64052, avg=12252.21, stdev=2690.49
     lat (usec): min=3193, max=64210, avg=12331.38, stdev=2689.03
   bw (  KiB/s): min=71680, max=254976, per=99.98%, avg=124514.84, stdev=797.60, samples=12112
   iops        : min=  560, max= 1992, avg=972.70, stdev= 6.23, samples=12112
*********Fio_Job**************
Tue Nov 21 11:14:26 UTC 2023 Sample=1; Block_Size=8k; job=randread; numjobs=4; iodepth=8
All clients: (groupid=0, jobs=3): err= 0: pid=0: Tue Nov 21 11:16:28 2023
  read: IOPS=11.2k, BW=87.6Mi (91.9M)(10.3GiB/120010msec)
    slat (nsec): min=828, max=2214.5k, avg=15320.86, stdev=12491.00
    clat (usec): min=2, max=263621, avg=8540.51, stdev=6527.22
     lat (usec): min=60, max=263673, avg=8555.83, stdev=6527.08
   bw (  KiB/s): min=55656, max=190247, per=99.87%, avg=89629.37, stdev=1079.02, samples=2868
   iops        : min= 9256, max=13381, avg=11214.21, stdev=101.67, samples=288
*********Fio_Job**************
Tue Nov 21 11:17:28 UTC 2023 Sample=2; Block_Size=8k; job=randread; numjobs=4; iodepth=8
All clients: (groupid=0, jobs=3): err= 0: pid=0: Tue Nov 21 11:19:30 2023
  read: IOPS=15.0k, BW=117Mi (123M)(13.7GiB/120012msec)
    slat (nsec): min=856, max=8217.2k, avg=16285.09, stdev=16324.93
    clat (nsec): min=635, max=83352k, avg=6389917.46, stdev=5329588.61
     lat (usec): min=59, max=83356, avg=6406.20, stdev=5329.49
   bw (  KiB/s): min=104215, max=338312, per=99.93%, avg=119774.21, stdev=1276.95, samples=2868
   iops        : min=14175, max=18503, avg=14979.38, stdev=74.24, samples=288
*********Fio_Job**************
Tue Nov 21 11:20:30 UTC 2023 Sample=1; Block_Size=16k; job=randread; numjobs=4; iodepth=8
All clients: (groupid=0, jobs=3): err= 0: pid=0: Tue Nov 21 11:22:32 2023
  read: IOPS=12.4k, BW=194Mi (204M)(22.8GiB/120009msec)
    slat (nsec): min=938, max=11718k, avg=13179.99, stdev=16166.82
    clat (nsec): min=897, max=216250k, avg=7711372.36, stdev=6135874.55
     lat (usec): min=69, max=216279, avg=7724.55, stdev=6135.78
   bw (  KiB/s): min=164268, max=474181, per=99.88%, avg=198572.18, stdev=1918.69, samples=2868
   iops        : min=10977, max=13660, avg=12421.83, stdev=69.74, samples=288
*********Fio_Job**************
Tue Nov 21 11:23:33 UTC 2023 Sample=2; Block_Size=16k; job=randread; numjobs=4; iodepth=8
All clients: (groupid=0, jobs=3): err= 0: pid=0: Tue Nov 21 11:25:34 2023
  read: IOPS=14.5k, BW=227Mi (238M)(26.6GiB/120008msec)
    slat (nsec): min=944, max=8610.9k, avg=13294.66, stdev=16890.65
    clat (nsec): min=656, max=64718k, avg=6598659.02, stdev=5373093.66
     lat (usec): min=57, max=64751, avg=6611.95, stdev=5372.90
   bw (  KiB/s): min=197664, max=638977, per=99.83%, avg=231858.26, stdev=2384.73, samples=2868
   iops        : min=13773, max=18777, avg=14513.33, stdev=82.57, samples=288
```

### Detailed fio output
For detailed fio output or to check fio output of previous fio run, one can view the fio output directory stored in the pvc `fio-data-pvc`
```
# oc rsh fio-storage

sh-4.2# ls -l /mnt
total 328
-rw-r--r--. 1 1000710000 1000710000 81920 Nov 21 11:23 fio_16k_randread_sample1_23_11_21_11_23.tar
-rw-r--r--. 1 1000710000 1000710000 81920 Nov 21 11:26 fio_16k_randread_sample2_23_11_21_11_26.tar
-rw-r--r--. 1 1000710000 1000710000 81920 Nov 21 11:17 fio_8k_randread_sample1_23_11_21_11_17.tar
-rw-r--r--. 1 1000710000 1000710000 81920 Nov 21 11:20 fio_8k_randread_sample2_23_11_21_11_20.tar
-rw-r--r--. 1 1000710000 1000710000  7862 Nov 21 11:13 prefill_output.log
```

### Formatted output
For quick generation of a comma separated file, run `./print_results.sh
```

# cat ~/simple-fio-results/results.csv
Cluster Name,PVC,Storage Type,Environment,Test Name,IO Size,Jobs,Depth,write MiB/s,Writes/s,Mean Write Latency (ms),95th Write Latency,read MiB/s,Reads/s,Mean Read Latency (ms),95th Read Latency,Total MiB/s,Total IOPS,Total Time (s)
IBM4Citi,fio-pv-claim,ocs-storagecluster-ceph-rbd,Data Foundation on Z,fio_test,8k,4,8,34.28,4388.81,7.29,14.87,0,0,0,0,35110,4388.817143,120
```

