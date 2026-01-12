#! /usr/bin/python3
import json
import os.path
import signal
import subprocess
import sys
import time

path_knowledge = "~/modules_analysis/config/knowledge.json"
path_syzgen = "Eager-SyzGen"

kernel_version = "v6.2"

name_config_json = "config.json"

time_run = 24 * 60 * 60

path_current = os.getcwd()


class Process:
    def __init__(self):
        self.cmd = ""
        self.path = ""
        self.processes = []
        self.cmd_template = ""

    def execute(self):
        self.path = path_current
        print(self.path)

        if not os.path.exists(os.path.join(path_current, name_config_json)):
            f = open(os.path.join(path_current, name_config_json), "w")
            f.write("{}")
            f.close()

        f = open(os.path.join(path_current, name_config_json), "r")
        c = json.load(f)
        f.close()

        c["bitcode"] = "built-in.bc"
        c["knowledge"] = path_knowledge
        c["version"] = kernel_version

        f = open(os.path.join(self.path, name_config_json), "w")
        json.dump(c, f, indent=4)
        f.close()

        self.cmd = path_syzgen + " --config=config.json 1>log.txt 2>&1"
        p = subprocess.Popen(self.cmd, shell=True)
        self.processes.append(p)

    def close(self):
        for p in self.processes:
            os.killpg(os.getpgid(p.pid), signal.SIGTERM)


def main():
    target = ""
    if len(sys.argv) > 1:
        target = sys.argv[1]

    if target == "":
        task = Process()
        task.execute()

    else:
        print("error arguments")

    time.sleep(time_run)

    task.close()


if __name__ == "__main__":
    main()
