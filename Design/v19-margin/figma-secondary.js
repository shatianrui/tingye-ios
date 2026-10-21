// Append after figma-ui.js and SVG source map.
function panel(name,x,y,title,kicker,rows,description=''){const s=screen(name,x,y);topbar(s.body,title);text(s.body,kicker,'Title','ink',342);if(description)text(s.body,description,'Small','ink2',342);const group=rounded(box(s.body,'Settings group','VERTICAL',342,0,16,'surface'));rows.forEach(([ic,title,value],i)=>{settingsRow(group,ic,title,value||'');if(i<rows.length-1)rule(group);});s.finish();return s.root;}
const roots=[];
roots.push(panel('导入 · 把书带进来',200,1520,'添加书籍','把书，带进来。',[
 ['folder','从文件导入','推荐'],['wifi','Wi-Fi 传书','同一网络'],['icloud','WebDAV','连接'],['book','OPDS 书源','浏览'],['folder','SMB','文件 App'],['list.bullet','最近导入结果','查看']
],'支持 TXT / EPUB / MOBI / PDF / DOCX / CBZ 等格式，文件保存在本机。'));
roots.push(panel('排版 · 你的阅读方式',650,1520,'阅读排版','读得舒服一点。',[
 ['textformat.size','字号','22'],['slider-horizontal-3','行间距','1.6'],['textformat.size','阅读字体','系统字体'],['book','阅读方式','分页'],['moon','纸色','宣纸'],['list.bullet','段落间距','适中']
],'这里的设置只影响阅读正文。已保存的字体和纸色不会被重置。'));
roots.push(panel('声音 · 系统与云朗读',1100,1520,'声音设置','每段文字，都有声音。',[
 ['speaker.wave.2','声音来源','系统'],['person-2','音色','晓晓'],['speedometer','朗读语速','1.0×'],['headphones','播放设备','AirPlay'],['person-2','分角色朗读','Beta'],['play-fill','试听声音','播放']
],'系统声音可以离线使用。云语音由设备直连服务商，需要你自己的密钥。'));
roots.push(panel('外观 · 日与夜',1550,1520,'外观','让界面，顺应时间。',[
 ['moon','跟随系统','已选'],['book','浅色','暖纸'],['moon','深色','石墨'],['textformat.size','应用字体','系统'],['bookmark','应用图标','折页声窗']
],'阅读正文拥有独立纸色。应用外观不会替换你的阅读偏好。'));
roots.push(panel('目录 · 定位与摘记',2000,1520,'目录与摘记','瓦尔登湖',[
 ['list.bullet','第一章  经济篇','1'],['list.bullet','第二章  我生活的地方','2'],['bookmark','第三章  声音','正在读'],['list.bullet','第四章  独处','4'],['list.bullet','第五章  访客','5'],['list.bullet','第六章  豆田','6']
],'目录  /  书签  /  摘记     ·     搜索本书'));
roots.push(panel('备份 · 你的书仍属于你',2450,1520,'备份与同步','安心保管。',[
 ['icloud','iCloud 手动快照','创建'],['folder','从备份恢复','选择'],['list.bullet','阅读位置同步','已开启'],['book','备份内容','书籍与摘记'],['folder','导出本地备份','导出']
],'快照包含书籍和阅读数据。自动同步仅同步位置，不会自动传输书籍。还原前始终确认。'));
roots.push(panel('设置 · 阅读偏好题录',200,2520,'设置','你的听页。',[
 ['textformat.size','阅读排版',''],['textformat.size','字体管理',''],['speaker.wave.2','声音与朗读',''],['moon','外观','跟随系统'],['folder','传书与来源',''],['icloud','备份与同步',''],['bookmark','书摘与笔记',''],['gearshape','隐私与关于','']
]));
roots.push(panel('字体 · 字的另一种样子',650,2520,'字体管理','字的另一种样子。',[
 ['textformat.size','系统字体','已选'],['textformat.size','思源宋体','内置'],['textformat.size','霞鹜文楷','内置'],['plus','导入字体','TTF / OTF']
],'山光悦鸟性，潭影空人心。\n\n字体可在设备上导入，阅读偏好独立保存。'));
roots.push(panel('书摘 · 留住心动一句',1100,2520,'书摘与笔记','留下来的文字。',[
 ['bookmark','书签','12'],['book','划线与笔记','8'],['folder','按书籍查看','全部'],['list.bullet','导出摘记','分享']
],'“我愿意深深地扎入生活，吮尽生活的骨髓。”\n\n瓦尔登湖 · 第三章\n示例摘句，非真实用户数据。'));
roots.push(panel('导入结果 · 每项都有回音',1550,2520,'导入结果','已导入 2 本。',[
 ['book','瓦尔登湖.epub','已完成'],['book','朝花夕拾.txt','已完成'],['folder','未识别的文件.zip','失败'],['plus','重新选择文件','重试']
],'失败原因：压缩包中未找到支持的书籍。成功的书籍已经放入书架。'));
roots.push(panel('Wi-Fi · 轻松传书',2000,2520,'Wi-Fi 传书','隔空，把书送来。',[
 ['wifi','本机传书地址','已启动'],['folder','接收的书籍','0 本'],['gearshape','停止服务','停止']
],'电脑和手机连接同一个 Wi-Fi，然后在浏览器打开本机显示的地址。离开页面后服务状态以实际运行结果为准。'));
const empty=screen('空书架 · 第一本书',2450,2520,0);header(empty.body,'书架','WELCOME TO TINGYE','plus');const ev=rounded(box(empty.body,'Empty state','VERTICAL',342,24,24,'hero'));text(ev,'从一本书开始。','Book');text(ev,'把喜欢的故事放进来。\n可以慢慢读，也可以合上眼睛听。','Body','ink2',294);button(ev,'导入书籍','primary',294);button(ev,'更多导入方式','secondary',294);text(empty.body,'支持 EPUB、TXT、PDF、MOBI 等格式。\n没有账号，书籍保存在你的设备。','Small','ink2',342);empty.finish();roots.push(empty.root);
const search=screen('搜索 · 快速找到那一本',200,3520,0);topbar(search.body,'搜索书架');const field=rounded(box(search.body,'Search field','HORIZONTAL',342,12,16,'surface'),16);icon(field,'magnifyingglass',18);text(field,'瓦尔登','Body');text(search.body,'找到 1 本书','Small','ink2');bookRow(search.body,'瓦尔登湖','亨利·戴维·梭罗','42%');search.finish();roots.push(search.root);
roots.push(panel('原书图文 · 保留出版版式',650,3520,'原书图文','瓦尔登湖',[
 ['list.bullet','目录','第三章'],['headphones','听书','从当前段落'],['book','切换文字阅读',''],['textformat.size','排版','原书']
],'原书图片与排版内容由导入的 EPUB 提供。图片不反色、不裁切；正文与听书定位分别控制。此帧说明阅读控件，书籍内容随原文件变化。'));
roots.push(panel('漫画 · 只留下画面',1100,3520,'漫画阅读','第 12 / 48 页',[
 ['book','阅读方向','从右向左'],['list.bullet','页面缩略图','48 页'],['moon','背景','深色'],['bookmark','阅读位置','已保存']
],'漫画内容由用户导入。画面完整呈现，轻点呼出工具，双指缩放。此帧展示工具状态，不使用虚构漫画填充。'));
roots.push(panel('定时 · 听到这里就好',1550,3520,'睡眠定时','听到这里，就好。',[
 ['moon','15 分钟',''],['moon','30 分钟','已选'],['moon','45 分钟',''],['moon','60 分钟',''],['list.bullet','本章结束',''],['moon','关闭定时','']
],'剩余时间按真实截止时间刷新，不将估算语音长度当作音频时长。'));
roots.push(panel('分角色 · 对话更生动',2000,3520,'分角色朗读','让对话，更生动。',[
 ['person-2','默认旁白','系统'],['person-2','角色一','选择声音'],['person-2','角色二','选择声音'],['plus','添加角色','']
],'Beta 功能，自动识别不保证准确。声音配置与原有朗读引擎一致。'));
roots.push(panel('隐私 · 安静也安心',2450,3520,'隐私与关于','只属于你的书房。',[
 ['gearshape','应用锁','关闭'],['book','隐藏书籍','验证后查看'],['folder','本机存储','管理'],['list.bullet','开源许可','查看'],['gearshape','关于听页','本地读听']
],'没有听页账号和自有服务器。系统声音离线工作，云语音连接遵循服务商说明。'));
const primaries=await Promise.all(['7:13','7:98','7:178','7:229','7:265','7:349'].map(id=>figma.getNodeByIdAsync(id)));
primaries.forEach((source,i)=>{const n=source.clone();n.name='Dark / '+source.name;n.x=200+450*i;n.y=4520;n.setExplicitVariableModeForCollection(cc,cc.modes.find(m=>m.name==='Dark').modeId);roots.push(n);ids.push(n.id,...n.findAll(()=>true).map(n=>n.id));});
const all=roots.flatMap(r=>[r,...r.findAll(()=>true)]);return {createdNodeIds:[...new Set([...ids,...all.map(n=>n.id)])],screens:roots.map(r=>({id:r.id,name:r.name,width:r.width,height:r.height})),counts:all.reduce((a,n)=>(a[n.type]=(a[n.type]||0)+1,a),{}),images:all.filter(n=>'fills'in n&&Array.isArray(n.fills)&&n.fills.some(f=>f.type==='IMAGE')).map(n=>({id:n.id,name:n.name}))};
