"""Extract the embedded bootstrap script from cloud-init.yaml: extract.py <yaml> <out>."""
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
open(sys.argv[2], "w").write(cfg["write_files"][0]["content"])
