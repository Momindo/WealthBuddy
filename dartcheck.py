import sys, re, os
def check(path):
    s=open(path).read(); i=0; n=len(s); stack=[]; line=1
    pairs={')':'(',']':'[','}':'{'}
    def err(m): print(f"{path}:{line}: {m}"); return False
    # modes: code stack holds brackets; strings handled inline with interpolation recursion
    mode=[('code',None)]
    while i<n:
        c=s[i]
        if c=='\n': line+=1
        m,info=mode[-1]
        if m=='code' or m=='interp':
            if s.startswith('//',i):
                j=s.find('\n',i); i=n if j<0 else j; continue
            if s.startswith('/*',i):
                j=s.find('*/',i); line+=s[i:j].count('\n'); i=j+2; continue
            raw=False
            if c=='r' and i+1<n and s[i+1] in '\'"' and (i==0 or not (s[i-1].isalnum() or s[i-1]=='_')):
                raw=True; i+=1; c=s[i]
            if c in '\'"':
                q=c*3 if s.startswith(c*3,i) else c
                mode.append(('str',(q,raw))); i+=len(q); continue
            if c in '([{':
                stack.append((c,line)); 
            elif c in ')]}':
                if m=='interp' and c=='}' and (not stack or stack[-1][0]!='{' or stack[-1][1]=='INTERP'):
                    pass
                if not stack: return err(f"unmatched {c}")
                top=stack.pop()
                if top[0]=='${':
                    if c!='}': return err(f"bad close {c} for interpolation")
                    mode.pop(); i+=1; continue
                if top[0]!=pairs[c]: return err(f"mismatch {top[0]} (line {top[1]}) vs {c}")
            i+=1; continue
        if m=='str':
            q,raw=info
            if not raw and c=='\\': i+=2; continue
            if s.startswith(q,i): mode.pop(); i+=len(q); continue
            if len(q)==1 and c=='\n': return err("newline in single-line string")
            if not raw and s.startswith('${',i):
                stack.append(('${',line)); mode.append(('interp',None)); i+=2; continue
            i+=1; continue
    if len(mode)>1: return err(f"unterminated {mode[-1]}")
    if stack: return err(f"unclosed {stack[-1]}")
    return True
ok=True
files=[os.path.join(d,f) for d,_,fs in os.walk('lib') for f in fs if f.endswith('.dart')]+[os.path.join('test',f) for f in os.listdir('test') if f.endswith('.dart')]
for f in files: ok&=check(f)
# imports resolve
for f in files:
    for imp in re.findall(r"^import '([^']+)'", open(f).read(), re.M):
        if imp.startswith('package:wealth_buddy/'): tgt='lib/'+imp[len('package:wealth_buddy/'):]
        elif imp.startswith('package:') or imp.startswith('dart:'): continue
        else: tgt=os.path.normpath(os.path.join(os.path.dirname(f),imp))
        if not os.path.exists(tgt): print(f"{f}: missing import {imp}"); ok=False
print("files:",len(files),"structure OK" if ok else "PROBLEMS FOUND")
