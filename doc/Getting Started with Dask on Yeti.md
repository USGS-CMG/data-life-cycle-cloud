Follow the instructions for [Getting started with Dask on Cheyenne](https://github.com/pangeo-data/pangeo/wiki/Getting-Started-with-Dask-on-Cheyenne), but because Yeti uses Slurm, change the job script to:
```
#!/bin/bash
#SBATCH -J dask
#SBATCH -n 20
#SBATCH -c 10
#SBATCH -p normal
#SBATCH -A woodshole
#SBATCH -t 01:00:00
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rsignell@usgs.gov
#SBATCH --output=%j-dask

# This writes a scheduler.json file into your home directory
# You can then connect with the following Python code
# >>> from dask.distributed import Client
# >>> client = Client(scheduler_file='~/scheduler.json')

source activate pangeo
rm -f scheduler.json
srun --mpi=pmi2 dask-mpi --nthreads 10 --memory-limit 60e9 --interface ib0
```

Then to print out the tunnelling command for Yeti instead of Cheyenne, change the Python script that starts the Jupyter Notebook server to:
```
#!/usr/bin/env python
from dask.distributed import Client
client = Client(scheduler_file='scheduler.json')

import socket
host = client.run_on_scheduler(socket.gethostname)

def start_jlab(dask_scheduler):
    import subprocess
    proc = subprocess.Popen(['jupyter', 'lab', '--ip', host, '--no-browser'])
    dask_scheduler.jlab_proc = proc

client.run_on_scheduler(start_jlab)


print("ssh -N -L 8787:%s:8787 -L 8888:%s:8888 yeti.cr.usgs.gov" % (host, host))
```
