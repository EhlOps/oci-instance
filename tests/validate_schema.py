"""Validate cloud-init.yaml against cloud-init's published v1 schema (fallback when the
`cloud-init schema` CLI is unavailable): validate_schema.py <yaml> <schema.json>."""
import sys, json, yaml, jsonschema
cfg = yaml.safe_load(open(sys.argv[1]))
schema = json.load(open(sys.argv[2]))
jsonschema.Draft4Validator(schema).validate(cfg)
print("schema OK")
