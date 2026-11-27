import json,sys,time,uuid,copy
# seed.py <messages.json> <variant: only|plus> <a saved messages.json with one repeating text>
d=json.load(open(sys.argv[3]))
now=time.time()-978307200
m=d['messages'][0]
m['body']='REPRO '+'x'*9
m['sendAt']=now-3600
if sys.argv[2]=='plus':
    o=copy.deepcopy(m); o['id']=str(uuid.uuid4()).upper(); o['body']='Later text'; o['sendAt']=now+86400; o.pop('repetition',None)
    d['messages'].append(o)
json.dump(d,open(sys.argv[1],'w'))
