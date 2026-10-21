// Figma use_figma script; run only in the v19 file. Creates missing foundations, not a published library.
const page = figma.currentPage;
page.name = '01 · 余白 / 全界面';
const fonts = [{family:'SF Pro',style:'Regular'},{family:'SF Pro',style:'Semibold'},{family:'SF Pro',style:'Bold'},{family:'Noto Serif SC',style:'Regular'},{family:'Noto Serif SC',style:'SemiBold'}];
await Promise.all(fonts.map(f=>figma.loadFontAsync(f)));
const rgb = hex => ({r:parseInt(hex.slice(0,2),16)/255,g:parseInt(hex.slice(2,4),16)/255,b:parseInt(hex.slice(4,6),16)/255});
const specs={bg:['F6F3EC','191B1A'],surface:['FFFDF8','242725'],surface2:['EDE8DE','303531'],ink:['292D29','F2EFE6'],ink2:['62665D','B9BDB2'],line:['DEDCD2','3C423C'],accent:['A44A2C','F0AD88'],accentSoft:['F5E6DA','48352C'],onAccent:['FFFFFF','322017'],marker:['E8CA91','D4B779'],onMarker:['35362B','252820'],hero:['EBE3D2','333A32'],heroInk:['292D29','F2EFE6'],onInk:['FFFDF8','292D29']};
const collections=await figma.variables.getLocalVariableCollectionsAsync();
let coll=collections.find(c=>c.name==='Margin / Semantic');
if(!coll){coll=figma.variables.createVariableCollection('Margin / Semantic');coll.renameMode(coll.defaultModeId,'Light');coll.addMode('Dark');}
const light=coll.modes.find(m=>m.name==='Light').modeId,dark=coll.modes.find(m=>m.name==='Dark').modeId;
const existing=await figma.variables.getLocalVariablesAsync();
const vars={};
for(const [name,values] of Object.entries(specs)){
 let v=existing.find(v=>v.name===name&&v.variableCollectionId===coll.id)||figma.variables.createVariable(name,coll,'COLOR');
 v.scopes=['FRAME_FILL','SHAPE_FILL','TEXT_FILL','STROKE_COLOR'];v.setVariableCodeSyntax('iOS','Theme.'+name);
 v.setValueForMode(light,rgb(values[0]));v.setValueForMode(dark,rgb(values[1]));vars[name]=v.id;
}
for(const [name,value,scope] of [['inset',24,'GAP'],['space/sm',8,'GAP'],['space/md',16,'GAP'],['space/lg',24,'GAP'],['radius',24,'CORNER_RADIUS'],['buttonRadius',16,'CORNER_RADIUS']]){
 let v=existing.find(v=>v.name===name&&v.variableCollectionId===coll.id)||figma.variables.createVariable(name,coll,'FLOAT');
 v.scopes=[scope];v.setValueForMode(light,value);v.setValueForMode(dark,value);v.setVariableCodeSyntax('iOS',name.includes('/')?'CGFloat('+value+')':'Theme.'+name);vars[name]=v.id;
}
const styleSpecs=[['Title',34,41,fonts[1]],['Section',19,26,fonts[1]],['Body',17,25,fonts[0]],['Small',13,19,fonts[0]],['Kicker',11,16,fonts[1]],['Book',22,32,fonts[4]],['Reading',20,36,fonts[3]],['Display',48,58,fonts[0]]];
const oldStyles=await figma.getLocalTextStylesAsync();const styles={};
for(const [name,size,line,font] of styleSpecs){const s=oldStyles.find(s=>s.name==='Margin/'+name)||figma.createTextStyle();s.name='Margin/'+name;s.fontName=font;s.fontSize=size;s.lineHeight={unit:'PIXELS',value:line};styles[name]=s.id;}
let statusInfo=null, libraryError=null;
try {
 const status=await figma.importComponentByKeyAsync('e01a1714aeec1a5a0a6453485bf16e975008b282');
 const temp=status.createInstance();const properties=temp.componentProperties;temp.remove();
 statusInfo={id:status.id,key:status.key,properties,width:status.width,height:status.height};
} catch(error) { libraryError=String(error); }
return {pageId:page.id,collection:{id:coll.id,light,dark},vars,styles,status:statusInfo,libraryError,mutatedNodeIds:[page.id],createdNodeIds:[],counts:{variables:Object.keys(vars).length,textStyles:Object.keys(styles).length}};
