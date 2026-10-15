"""Mafateeh world kit: Diriyah-style mud architecture (curved, tapering walls, parapets that
rise at the corners, clustered triangle vents, beam ends, arched openings) and low-poly palms.
Usage: python3 tools/blender/build_courtyard.py [-- out_dir]   (default assets/world)
Writes courtyard.glb (VR courtyard, main door as node "DoorMain" hinged at its left edge),
door_arch.glb (free-standing mud gate for mixed reality, door "DoorMain") and palm.glb.
Textures are painted procedurally (NumPy + PIL) and embedded. Deterministic.
"""
import bpy, bmesh, math, os, sys, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from mathutils import Vector as V
A=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
HERE=os.path.dirname(os.path.abspath(__file__))
OUT=os.path.abspath(A[0] if A else os.path.join(HERE,'../../assets/world'))
TEX=os.path.join(HERE,'../../art_source/world/textures'); os.makedirs(TEX,exist_ok=True); os.makedirs(OUT,exist_ok=True)

def paint_textures():
    rng=np.random.default_rng(11)
    def smooth_noise(n, seed):
        r=np.random.default_rng(seed); acc=np.zeros((n,n))
        for o,s in enumerate([4,8,16,32,64,128]):
            g=Image.fromarray((r.random((s,s))*255).astype(np.uint8)).resize((n,n),Image.BICUBIC)
            acc+=np.asarray(g,float)/255/(1.6**o)
        acc-=acc.min(); return acc/acc.max()
    def save(name,a): Image.fromarray(np.clip(a,0,255).astype(np.uint8)).save(os.path.join(TEX,name+'.png'))
    N=512
    n=smooth_noise(N,1); f=smooth_noise(N,2)
    mud=np.array([200,152,108])*(0.84+0.22*n[...,None])*(0.96+0.07*f[...,None])
    fl=rng.random((N,N))>0.997; mud[fl]=mud[fl]*1.12; save('mud',mud)
    n=smooth_noise(N,5); save('sand',np.array([212,182,140])*(0.9+0.12*n[...,None]))
    W,H=256,512; n=smooth_noise(512,6)[:H,:W]
    d=np.array([126,86,56])*(0.85+0.2*n[...,None])
    for x in range(0,W,32): d[:,x:x+2]=[86,58,38]
    im=Image.fromarray(np.clip(d,0,255).astype(np.uint8)); dr=ImageDraw.Draw(im)
    def tri_row(y,col,h=14,step=24):
        for x in range(6,W-10,step): dr.polygon([(x,y+h),(x+step/2-2,y),(x+step-4,y+h)],fill=col)
    for y,col in [(30,(196,64,52)),(150,(232,184,75)),(330,(42,140,135)),(460,(196,64,52))]: tri_row(y,col)
    for cy in (100,250,400):
        for cx in (64,192):
            dr.polygon([(cx,cy-36),(cx+30,cy),(cx,cy+36),(cx-30,cy)],outline=(232,184,75),width=4)
            dr.polygon([(cx,cy-16),(cx+13,cy),(cx,cy+16),(cx-13,cy)],fill=(42,140,135))
            dr.ellipse([cx-4,cy-4,cx+4,cy+4],fill=(244,237,224))
    for y in (192,372):
        for x in range(12,W,20): dr.ellipse([x-3,y-3,x+3,y+3],fill=(244,237,224))
    im.save(os.path.join(TEX,'door.png'))
paint_textures()
MODE='kit'
random.seed(4)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc=bpy.context.scene; 
mats={}
def mat(name, img=None, color=(1,1,1), rough=0.95):
    if name in mats: return mats[name]
    m=bpy.data.materials.new(name); m.use_nodes=True; nt=m.node_tree; b=nt.nodes['Principled BSDF']
    b.inputs['Roughness'].default_value=rough; b.inputs['Base Color'].default_value=(*color,1)
    if img:
        t=nt.nodes.new('ShaderNodeTexImage'); t.image=bpy.data.images.load(os.path.join(TEX,img+'.png'))
        nt.links.new(t.outputs['Color'], b.inputs['Base Color'])
    mats[name]=m; return m
MUD=mat('mud','mud'); SAND=mat('sand','sand'); DOOR=mat('door','door',rough=0.8)
DARK=mat('vent',None,(0.09,0.06,0.045)); WOOD=mat('wood',None,(0.33,0.22,0.14),0.85)
LEAF=mat('leaf',None,(0.23,0.42,0.14),0.85); LEAF2=mat('leaf2',None,(0.34,0.52,0.18),0.85)
TRUNK=mat('trunk',None,(0.45,0.34,0.23)); DATES=mat('dates',None,(0.55,0.28,0.10),0.6)

def uv_box(bm,tile=2.2):
    uv=bm.loops.layers.uv.verify()
    for f in bm.faces:
        n=f.normal; ax=max(range(3),key=lambda i:abs(n[i]))
        for l in f.loops:
            co=l.vert.co; u,v=((co.y,co.z) if ax==0 else (co.x,co.z) if ax==1 else (co.x,co.y)); l[uv].uv=(u/tile,v/tile)
def finish(bm,name,m,smooth=True,subdiv=0,disp=0.0,flat=False):
    me=bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o=bpy.data.objects.new(name,me); sc.collection.objects.link(o); me.materials.append(m)
    if subdiv or disp:
        if subdiv:
            s=o.modifiers.new('s','SUBSURF'); s.levels=subdiv; s.render_levels=subdiv
        if disp:
            tx=bpy.data.textures.new(name+'n','CLOUDS'); tx.noise_scale=0.9; tx.noise_depth=2
            d=o.modifiers.new('d','DISPLACE'); d.texture=tx; d.strength=disp; d.mid_level=0.5; d.texture_coords='GLOBAL'
        dg=bpy.context.evaluated_depsgraph_get(); new=bpy.data.meshes.new_from_object(o.evaluated_get(dg))
        o.modifiers.clear(); old=o.data; o.data=new; bpy.data.meshes.remove(old)
        bm2=bmesh.new(); bm2.from_mesh(o.data); uv_box(bm2); bm2.to_mesh(o.data); bm2.free()
    for p in o.data.polygons: p.use_smooth=(smooth and not flat)
    return o

def rounded_rect(cx,cy,sx,sy,r,step=0.45):
    pts=[]; hx,hy=sx/2-r,sy/2-r
    corners=[(hx,hy,0),( -hx,hy,90),(-hx,-hy,180),(hx,-hy,270)]
    # walk counter-clockwise: right edge up... build from corner arcs and straight runs
    seq=[]
    for i,(ox,oy,a0) in enumerate(corners):
        for k in range(6):
            a=math.radians(a0+k*90/5); seq.append((cx+ox+r*math.cos(a), cy+oy+r*math.sin(a), i))
    # densify straight runs
    out=[]
    for i in range(len(seq)):
        p=V(seq[i][:2]); q=V(seq[(i+1)%len(seq)][:2]); n=max(1,int((q-p).length/step))
        for k in range(n): out.append(p.lerp(q,k/n))
    return out

def organic_block(name,cx,cy,sx,sy,h,r=0.8,taper=0.28,horn=1.0,par_h=0.55,par_t=0.32,seed=0,corner_boost=(1,1,1,1)):
    """Mud block with soft corners, tapering walls and a parapet that rises in horns at the corners."""
    rnd=random.Random(seed)
    ring=rounded_rect(cx,cy,sx,sy,r)
    c=V((cx,cy)); bm=bmesh.new()
    corner_pts=[V((cx+s1*(sx/2),cy+s2*(sy/2))) for s1,s2 in ((1,1),(-1,1),(-1,-1),(1,-1))]
    def inset(p,amt):
        d=(p-c); 
        # shrink toward centre along the dominant axis direction (keeps straight walls straight)
        nx=d.x/(sx/2); ny=d.y/(sy/2)
        return V((p.x-amt*max(-1,min(1,nx*1.0)), p.y-amt*max(-1,min(1,ny*1.0))))
    levels=[0.0,0.05,0.4,0.75,0.95,1.0]
    rings=[]
    for lv in levels:
        z=lv*h; amt=taper*lv
        rings.append([bm.verts.new((inset(p,amt).x,inset(p,amt).y,z)) for p in ring])
    n=len(ring)
    for a,b in zip(rings,rings[1:]):
        for i in range(n): bm.faces.new([a[i],a[(i+1)%n],b[(i+1)%n],b[i]])
    # parapet: outer = top ring raised, inner = inset ring
    def hp(p):
        dmin=min(((p-q).length/(1.0+0.4*r), k) for k,q in enumerate(corner_pts))
        d,k=dmin
        return par_h + horn*corner_boost[k]*max(0.0,1.0-d*0.75)**1.6 + 0.06*math.sin(p.x*1.7+p.y*1.3+seed)
    top=rings[-1]
    outer=[bm.verts.new((v.co.x,v.co.y,h+hp(V(v.co[:2])))) for v in top]
    innerT=[bm.verts.new((inset(V(v.co[:2]),par_t).x,inset(V(v.co[:2]),par_t).y,h+hp(V(v.co[:2]))-0.04)) for v in top]
    innerB=[bm.verts.new((inset(V(v.co[:2]),par_t).x,inset(V(v.co[:2]),par_t).y,h-0.05)) for v in top]
    for i in range(n):
        j=(i+1)%n
        bm.faces.new([top[i],top[j],outer[j],outer[i]])
        bm.faces.new([outer[i],outer[j],innerT[j],innerT[i]])
        bm.faces.new([innerT[i],innerT[j],innerB[j],innerB[i]])
    bm.faces.new(innerB[::-1])
    bm.faces.new([v for v in rings[0]][::-1])
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
    return finish(bm,name,MUD,subdiv=1,disp=0.05)

def facade_point(cx,cy,sx,sy,h,taper,side,t,z):
    """Point on a block facade ('+y','-y','+x','-x') at fraction t along it and height z (follows the taper)."""
    k=taper*z/h
    if side in('+y','-y'):
        y=cy+(sy/2-k)*(1 if side=='+y' else -1); x=cx-sx/2+0.9+t*(sx-1.8); n=V((0,1 if side=='+y' else -1,0))
    else:
        x=cx+(sx/2-k)*(1 if side=='+x' else -1); y=cy-sy/2+0.9+t*(sy-1.8); n=V((1 if side=='+x' else -1,0,0))
    return V((x,y,z)),n

def tri(c,n,w,h,m=DARK):
    bm=bmesh.new(); side=V((-n.y,n.x,0)); up=V((0,0,1)); lean=V((n.x,n.y,0))*0.0
    pts=[c-side*w/2, c+side*w/2, c+up*h]
    vs=[bm.verts.new(p+n*0.06) for p in pts]+[bm.verts.new(p-n*0.05) for p in pts]
    bm.faces.new(vs[0:3]); bm.faces.new(vs[3:6][::-1])
    for i in range(3):
        j=(i+1)%3; bm.faces.new([vs[i],vs[j],vs[j+3],vs[i+3]])
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces); return finish(bm,'vent',m,smooth=False)

def vent_cluster(blk,side,t,z,rows=3,size=0.17):
    """Triangular cluster of triangular vents: 1,2,3... from the top down."""
    for r in range(rows):
        for k in range(r+1):
            off=(k-r/2)*size*1.35/ max(1,1)
            p,n=facade_point(*blk,side,t,z-r*size*1.25)
            sidev=V((-n.y,n.x,0)); tri(p+sidev*off,n,size,size*1.2)

def vent_row(blk,side,z,count,size=0.16,skip=()):
    for i in range(count):
        t=(i+0.5)/count
        if any(abs(t-s)<0.09 for s in skip): continue
        p,n=facade_point(*blk,side,t,z); tri(p,n,size,size*1.3)

def opening(blk,side,t,z,w,h,m=DARK,arch=True):
    p,n=facade_point(*blk,side,t,z); bm=bmesh.new(); s=V((-n.y,n.x,0))
    pts=[]; segs=8
    pts.append(p-s*w/2); pts.append(p+s*w/2); pts.append(p+s*w/2+V((0,0,h)))
    if arch:
        for k in range(1,segs): a=math.pi*k/segs; pts.append(p+s*(w/2*math.cos(a))+V((0,0,h+w*0.3*math.sin(a))))
    pts.append(p-s*w/2+V((0,0,h)))
    f=[bm.verts.new(q+n*0.07) for q in pts]; b=[bm.verts.new(q-n*0.08) for q in pts]
    bm.faces.new(f); bm.faces.new(b[::-1])
    for i in range(len(pts)):
        j=(i+1)%len(pts); bm.faces.new([f[i],f[j],b[j],b[i]])
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces); uv_box(bm,1.0)
    return finish(bm,'opening',m,smooth=False)

def door(blk,side,t,name='DoorMain'):
    p,n=facade_point(*blk,side,t,0.0); s=V((-n.y,n.x,0)); w,h=1.15,2.05
    opening(blk,side,t,0.0,w+0.3,h+0.15,m=DARK)
    bm=bmesh.new(); q=p+n*0.09; hinge=q-s*w/2
    vs=[bm.verts.new(q-s*w/2-hinge),bm.verts.new(q+s*w/2-hinge),bm.verts.new(q+s*w/2+V((0,0,h))-hinge),bm.verts.new(q-s*w/2+V((0,0,h))-hinge)]
    f=bm.faces.new(vs); uv=bm.loops.layers.uv.verify()
    for l,(u,v) in zip(f.loops,[(0,0),(1,0),(1,1),(0,1)]): l[uv].uv=(u,v)
    bmesh.ops.recalc_face_normals(bm,faces=[f])
    if f.normal.dot(n)<0: f.normal_flip()
    me=bpy.data.meshes.new(name); bm.to_mesh(me); bm.free(); o=bpy.data.objects.new(name,me); o.location=hinge; sc.collection.objects.link(o); me.materials.append(DOOR)
    return o

def beams(blk,side,z,count):
    for i in range(count):
        p,n=facade_point(*blk,side,(i+0.5)/count,z)
        bm=bmesh.new(); bmesh.ops.create_cone(bm,cap_ends=True,segments=7,radius1=0.07,radius2=0.065,depth=0.36)
        from mathutils import Matrix
        rot=V((0,0,1)).rotation_difference(n).to_matrix().to_4x4()
        bmesh.ops.transform(bm,matrix=rot,verts=bm.verts); bmesh.ops.translate(bm,verts=bm.verts,vec=p+n*0.12)
        finish(bm,'beam',WOOD,smooth=False)

# ---- low poly palm
def palm(x,y,h=6.0,seed=0):
    rnd=random.Random(seed); bend=V((rnd.uniform(-0.6,0.6),rnd.uniform(-0.6,0.6),0))
    bm=bmesh.new(); seg=7; ringsN=9; prev=None
    for i in range(ringsN+1):
        t=i/ringsN; z=t*h; r=0.24-0.08*t; off=bend*(t*t)
        ring=[bm.verts.new((x+off.x+r*math.cos(a*math.tau/seg+(i%2)*0.3), y+off.y+r*math.sin(a*math.tau/seg+(i%2)*0.3), z)) for a in range(seg)]
        if prev:
            for k in range(seg): bm.faces.new([prev[k],prev[(k+1)%seg],ring[(k+1)%seg],ring[k]])
        prev=ring
    finish(bm,'trunk',TRUNK,smooth=False)
    top=V((x,y,h))+bend
    fr=14
    for k in range(fr):
        a=k*math.tau/fr+rnd.uniform(-0.12,0.12); L=rnd.uniform(2.4,3.0); droop=rnd.uniform(1.6,2.4)
        d=V((math.cos(a),math.sin(a),0)); side=V((-d.y,d.x,0))
        bm=bmesh.new(); segs=4; spine=[]; left=[]; right=[]
        for s in range(segs+1):
            t=s/segs; w=0.42*math.sin(math.pi*min(1,t*1.1))+0.03
            p=top+d*(L*t)+V((0,0,(0.7 if k%2 else 0.35)*t-droop*t*t))
            spine.append(bm.verts.new(p+V((0,0,0.06)))); left.append(bm.verts.new(p+side*w-V((0,0,0.08)))); right.append(bm.verts.new(p-side*w-V((0,0,0.08))))
        for s in range(segs):
            bm.faces.new([spine[s],spine[s+1],left[s+1],left[s]]); bm.faces.new([spine[s],right[s],right[s+1],spine[s+1]])
        bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
        finish(bm,'frond',LEAF if k%2 else LEAF2,smooth=False)
    for k in range(3):  # date clusters
        a=k*math.tau/3+0.5; bm=bmesh.new(); bmesh.ops.create_icosphere(bm,subdivisions=1,radius=0.22)
        bmesh.ops.translate(bm,verts=bm.verts,vec=top+V((0.35*math.cos(a),0.35*math.sin(a),-0.35))); finish(bm,'dates',DATES,smooth=False)


def clear():
    for o in list(bpy.data.objects): bpy.data.objects.remove(o,do_unlink=True)
def export(name):
    bpy.ops.object.select_all(action='SELECT')
    path=os.path.join(OUT,name+'.glb')
    bpy.ops.export_scene.gltf(filepath=path,export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_image_format='JPEG',export_jpeg_quality=85)
    tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in bpy.data.objects if o.type=='MESH')
    print('exported',path,os.path.getsize(path)//1024,'KB',tris,'tris')

# ---- courtyard (VR, life size). Blender +Y = north (Godot -Z).
bm=bmesh.new(); bmesh.ops.create_grid(bm,x_segments=1,y_segments=1,size=40); uv_box(bm,4.0); finish(bm,'Ground',SAND)
N=( -1.0, 7.0, 13.0, 6.0, 6.8)
organic_block('north',N[0],N[1],N[2],N[3],N[4],r=1.0,taper=0.32,horn=1.3,seed=1,corner_boost=(1.4,0.6,1,1))
organic_block('north_hi',-4.6,8.2,5.0,3.6,8.6,r=0.8,taper=0.3,horn=1.2,seed=8,corner_boost=(1,1.5,1,0.8))
T=( 4.4, 7.6, 3.0, 3.0, 9.6)
organic_block('tower',T[0],T[1],T[2],T[3],T[4],r=0.9,taper=0.42,horn=1.1,par_h=0.4,seed=2)
W=(-7.6, 0.2, 4.2, 9.0, 4.4)
organic_block('west',W[0],W[1],W[2],W[3],W[4],r=0.9,taper=0.22,horn=0.9,seed=3,corner_boost=(1.2,1,1,0.5))
organic_block('eastwall',6.0,-0.6,0.8,8.4,2.6,r=0.35,taper=0.08,horn=0.6,par_h=0.25,par_t=0.3,seed=4)
organic_block('south_l',-3.8,-4.9,4.6,0.8,2.3,r=0.35,taper=0.08,horn=0.7,par_h=0.25,par_t=0.3,seed=5)
organic_block('south_r',3.6,-4.9,4.4,0.8,2.3,r=0.35,taper=0.08,horn=0.7,par_h=0.25,par_t=0.3,seed=6)
blkN=(N[0],N[1],N[2],N[3],N[4],0.32); blkW=(W[0],W[1],W[2],W[3],W[4],0.22); blkT=(T[0],T[1],T[2],T[3],T[4],0.42)
door(blkN,'-y',0.5,'DoorMain'); door(blkW,'+x',0.4,'DoorWest')
beams(blkN,'-y',3.4,12)
vent_row(blkN,'-y',5.6,14,skip=(0.5,))
vent_cluster(blkN,'-y',0.5,6.3,rows=3)
for t in (0.18,0.82): opening(blkN,'-y',t,1.6,0.55,0.75); opening(blkN,'-y',t,4.0,0.5,0.7)
vent_row(blkW,'+x',3.3,8,skip=(0.4,)); opening(blkW,'+x',0.78,1.4,0.5,0.7)
vent_cluster(blkT,'-y',0.5,8.6,rows=4,size=0.15); vent_row(blkT,'-y',6.2,4); opening(blkT,'-y',0.5,4.4,0.45,0.8)
palm(-3.6,1.6,6.4,1); palm(9.5,3.0,7.0,3); palm(-11,6,6.6,4); palm(10,-8,6.0,5)
export('courtyard')

# ---- free-standing mud gate for mixed reality (stands on the room floor, faces -Y = towards the player)
clear()
G=(0.0,0.0,2.6,0.6,2.9)
organic_block('gate',G[0],G[1],G[2],G[3],G[4],r=0.25,taper=0.12,horn=0.55,par_h=0.2,par_t=0.18,seed=9,corner_boost=(1.2,1.2,1,1))
blkG=(G[0],G[1],G[2],G[3],G[4],0.12)
door(blkG,'-y',0.5,'DoorMain')
vent_cluster(blkG,'-y',0.5,2.75,rows=2,size=0.12)
export('door_arch')

clear(); palm(0,0,4.2,6); export('palm')
