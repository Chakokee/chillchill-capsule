import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
if not data.get('fail_closed', True):
    raise SystemExit('Policy set to fail-open')
print('Policy OK')
