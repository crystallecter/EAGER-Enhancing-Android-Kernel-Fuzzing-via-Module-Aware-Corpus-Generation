import subprocess
import networkx as nx
from pathlib import Path

modules_dir = Path("./")

ko_files = list(modules_dir.glob("*.ko"))
print(len(ko_files))
module_paths = {ko.stem: ko for ko in ko_files}
dep_graph = nx.DiGraph()

for mod_name, ko_path in module_paths.items():
    try:
        output = subprocess.check_output(["modinfo", str(ko_path)], text=True)
        dep_graph.add_node(mod_name)
        for line in output.splitlines():
            if line.startswith("depends:"):
                deps = line.split(":", 1)[1].strip()
                for dep in deps.split(","):
                    dep = dep.strip()
                    if dep:
                        dep_graph.add_edge(dep, mod_name)
    except subprocess.CalledProcessError:
        continue

try:
    sorted_modules = list(nx.topological_sort(dep_graph))
    print("Topologically sorted load order:")
    for mod in sorted_modules:
        print("load ", mod)

    missing = set(dep_graph.nodes) - set(sorted_modules)
    if missing:
        print(" Modules ignored or isolated (no deps & not depended on):")
        for mod in sorted(missing):
            print("load ", mod)
except nx.NetworkXUnfeasible:
    print("There is a circular dependency! Unable to sort.")

