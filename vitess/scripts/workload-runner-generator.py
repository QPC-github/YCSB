import json
import sys

def main(unused_argv):
  vtgate_host = sys.argv[1]
  with open('workloads.json') as data_file:
    data = json.load(data_file)

  with open('workload-runner.sh','w') as cmd_file:
    for index, workload in enumerate(data["workloads"]):
      action = workload["action"]
      cmd = 'YCSB/bin/ycsb %s vitess -P YCSB/workloads/workload%s -p hosts=%s -p keyspace=test_keyspace -p insertorder=ordered -p recordcount=%s -threads %s -s' % (
                      action, workload["workload"], vtgate_host, workload['recordcount'], workload["threads"])
      if action == 'run':
        cmd += ' -p operationcount=%s -p tabletType=replica' % workload['operationcount']
      if not (workload.has_key('createtable') and workload['createtable'] == 'True'):
        cmd += ' -p createTable=skip'
      cmd_file.write('%s > ~/workloadlogs/workload%s%02d.txt\n' % (cmd, workload["workload"], index))
      if action == 'load':
        cmd_file.write('sleep 30\n')

if __name__ == '__main__':
  main(sys.argv)
