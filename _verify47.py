import re
src = open("Tweak.x", encoding="utf-8").read().splitlines()
def line(n): return src[n-1]

print("=== 1. DOCK-FOREIGN RDLog (L2251): % specifiers vs args ===")
stmt=[]
for i in range(2250, 2260):
    stmt.append(src[i])
    if ");" in src[i]: break
joined=" ".join(stmt)
specs=re.findall(r'%(?:\.\d+)?[d@sfp]', joined)
print("  % specifiers:", len(specs), specs)
m=re.search(r'@",\s*(.*?)\);', joined, re.S)
if m:
    body=m.group(1)
    depth=0; cnt=1; instr=False
    for ch in body:
        if ch=='"': instr=not instr
        if not instr:
            if ch in '([{': depth+=1
            elif ch in ')]}': depth-=1
            elif ch==',' and depth==0: cnt+=1
    print("  approx arg count:", cnt)
    print("  MATCH" if cnt==len(specs) else "  *** MISMATCH ***")

print()
print("=== 2. ASCII quote parity for .47 string-literal lines ===")
for ln in [4917, 4930, 2251]:
    s=line(ln)
    q=s.count('"')
    print(f"  L{ln}: total quotes = {q}  -> {'OK (even)' if q%2==0 else '*** ODD -> likely broken ***'}")

print()
print("=== 3. L4930 build note: single @\"...\" string well-formed? ===")
s4930=line(4930)
i=s4930.find('@"')
ok=False
if i>=0:
    j=i+2
    while j<len(s4930):
        c=s4930[j]
        if c=='\\':
            j+=2; continue
        if c=='"':
            ok=True; break
        j+=1
    inner=s4930[i+2:j]
    print("  closing quote found:", ok)
    print("  string length:", len(inner))
    print("  inner contains unescaped ASCII quote:", '"' in inner, "(should be False)")
    print("  line ends with ); :", s4930.rstrip().endswith(');'))

print()
print("=== 4. kMKDockPinnedKey: set once, cleared in BOTH restore paths ===")
sets=[i+1 for i,l in enumerate(src) if 'objc_setAssociatedObject' in l and 'kMKDockPinnedKey' in l and '@YES' in l]
clears=[i+1 for i,l in enumerate(src) if 'objc_setAssociatedObject' in l and 'kMKDockPinnedKey' in l and 'nil' in l]
reads=[i+1 for i,l in enumerate(src) if 'objc_getAssociatedObject' in l and 'kMKDockPinnedKey' in l]
print("  SET (@YES):", sets, "(expect 1)")
print("  CLEAR (nil):", clears, "(expect >=2: cache-hit + rebind)")
print("  READ (guard):", reads)

print()
print("=== 5. definition-before-use ===")
defline_ex=next(i+1 for i,l in enumerate(src) if l.startswith('static UIView *MKGetCachedLabelEx'))
defline_probe=next(i+1 for i,l in enumerate(src) if l.startswith('static void MKDockForeignProbe'))
defline_stray=next(i+1 for i,l in enumerate(src) if l.startswith('static BOOL MKDockStrayHide'))
fwd=next((i+1 for i,l in enumerate(src) if 'MKGetCachedLabel(SBIconView *iv);' in l and l.strip().startswith('static')),None)
print(f"  forward decl MKGetCachedLabel @ L{fwd}")
print(f"  MKGetCachedLabelEx def @ L{defline_ex}")
uses_ex=[i+1 for i,l in enumerate(src) if 'MKGetCachedLabelEx(' in l and not l.strip().startswith('//') and 'static UIView *MKGetCachedLabelEx' not in l]
print("    uses:", uses_ex, "-> all > def?", all(u>defline_ex for u in uses_ex))
print(f"  MKDockForeignProbe def @ L{defline_probe}")
uses_probe=[i+1 for i,l in enumerate(src) if 'MKDockForeignProbe(' in l and not l.strip().startswith('//') and 'static void MKDockForeignProbe' not in l]
print("    uses:", uses_probe, "-> all > def?", all(u>defline_probe for u in uses_probe))
print(f"  MKDockStrayHide def @ L{defline_stray} (> Ex & > Probe):", defline_stray>defline_ex and defline_stray>defline_probe)

print()
print("=== 6. balance: braces/parens in MKDockStrayHide body (L2261-end) ===")
start=defline_stray-1
# find function end by brace matching from the opening {
depth=0; began=False; endln=None
for k in range(start, min(start+120,len(src))):
    for ch in src[k]:
        if ch=='{': depth+=1; began=True
        elif ch=='}': depth-=1
        if began and depth==0: endln=k+1; break
    if endln: break
print("  MKDockStrayHide spans L%d..L%d"%(defline_stray,endln))
seg="".join(src[defline_stray-1:endln])
print("  braces { } balanced:", seg.count('{')==seg.count('}'), "(%d/%d)"%(seg.count('{'),seg.count('}')))
print("  parens ( ) balanced:", seg.count('(')==seg.count(')'), "(%d/%d)"%(seg.count('('),seg.count(')')))
