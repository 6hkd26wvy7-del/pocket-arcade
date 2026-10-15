window.__calls=[];
window.supabase = { createClient: function(){
  var me={pseudo:'Quentin',country:'FR',avatar:'av_01',featured_badge:null,xp:800,level:5,level_start_xp:800,next_level_xp:1250,bc:300,badges:['first_game','beta_founder'],items:[],streak:1,daily_claimed_today:true};
  var blocked=[]; var friends=[{pseudo:'Zoe',level:5,relation:'friend',avatar:'av_05',featured_badge:'beta_founder'},{pseudo:'Bob',level:3,relation:'incoming',avatar:'av_02',featured_badge:null}];
  var ok=function(d){return Promise.resolve({data:d,error:null})};
  var err=function(m){return Promise.resolve({data:null,error:{message:m}})};
  var tables={ badges:[{code:'first_game',name:'Premiers pas',description:'Termine ta première partie.',exclusive:false},{code:'beta_founder',name:'BÊTA TESTEUR — ÉDITION FONDATRICE',description:'Un des 10 premiers.',exclusive:true},{code:'founder',name:'FONDATEUR',description:'Le créateur.',exclusive:true}], news:[], shop_items:[] };
  return {
   auth:{ onAuthStateChange:function(fn){ fn('INITIAL_SESSION',{user:{id:'u1',email:'a@b.fr'}}); }, signOut:function(){return ok({})} },
   storage:{ from:function(){ return { createSignedUrl:function(p){ (window.__signed=window.__signed||[]).push(p); return ok({signedUrl:'data:,'}); } }; } },
   from:function(t){ return { select:function(){ return { eq:function(){return {maybeSingle:function(){return ok({pseudo:'Quentin',country:'FR'})}}}, order:function(){ var r=ok(tables[t]||[]); r.limit=function(){return ok(tables[t]||[])}; return r; } }; } } },
   rpc:function(n,a){
    window.__calls.push(n+(a?JSON.stringify(a):''));
    switch(n){
     case 'me': return ok(me);
     case 'my_missions': return ok([]);
     case 'my_role': return ok('founder');
     case 'staff_export': return ok(window.__EXP);
     case 'my_notifications': return ok([]);
     case 'get_maintenance': return ok({on:false,message:''});
     case 'my_friends': return ok(friends);
     case 'my_blocks': return ok(blocked.map(function(p){return {pseudo:p}}));
     case 'public_profile': return a.p_pseudo==='Zoe' ? ok({pseudo:'Zoe',avatar:'av_05',level:5,relation:'friend',featured_badge:{code:'beta_founder',name:'BÊTA TESTEUR — ÉDITION FONDATRICE'},title:{code:'title_legend',name:'LÉGENDE'},xp:900,games:[{game:'snake',best:42,plays:7},{game:'blocks',best:1200,plays:2}],badges:['beta_founder']} ) : ok({pseudo:a.p_pseudo,avatar:'av_02',level:3,relation:'pending',featured_badge:null,title:null,xp:null,games:null,badges:null});
     case 'block_user': blocked.push(a.p_pseudo); friends=friends.filter(function(f){return f.pseudo!==a.p_pseudo}); return ok(null);
     case 'unblock_user': blocked=blocked.filter(function(p){return p!==a.p_pseudo}); return ok(null);
     case 'set_avatar': me.avatar=a.p_code; return ok(null);
     case 'set_featured_badge': me.featured_badge=a.p_code||null; return ok(null);
     case 'conversation': return ok([{id:1,mine:false,body:'Salut !'}]);
     case 'submit_bug_report': window.__bug=a; return a.p_description.length<10?err('invalid description'):ok(42);
     case 'staff_bug_counts': return ok([{status:'new',n:2},{status:'resolved',n:1}]);
     case 'staff_bug_list': return ok([{id:42,created_at:'2026-10-15T10:00:00Z',pseudo:'joh',category:'game',description:'Le serpent traverse le mur apres la pause, je ne comprends pas pourquoi.',page:'#snake',game:'snake',app_version:'2026.10.15-a',device:{ua:'iPhone',viewport:'390x700'},has_screenshot:true,status:'new',priority:'high',admin_note:''},{id:41,created_at:'2026-10-14T10:00:00Z',pseudo:'tintintest',category:'display',description:'Bouton sous la barre.',page:'#menu',game:'',app_version:'x',device:{},has_screenshot:false,status:'resolved',priority:'low',admin_note:'ok'}]);
     case 'staff_bug_screenshot': return ok('data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=');
     case 'staff_bug_update': window.__upd=a; return ok(null);
     case 'staff_economy': return ok({settings:{game_bc:{snake:{div:10,cap:null},blocks:{div:200,cap:25},space:{div:100,cap:25},boyblocks:{div:400,cap:25}},game_bc_daily_cap:150,daily_streak:[10,15,20,25,30,40,100],season_rewards:{rank1:500,rank3:300,rank10:150,other:30}},shop:[{code:'title_rookie',name:'Titre : Recrue',kind:'title',price:50}],missions:[{code:'play_3',name:'Joue 3 parties',bc:20,xp:20}],log:[]});
     case 'staff_economy_set': (window.__eco=window.__eco||[]).push(a); return ok(null);
     case 'staff_set_price': (window.__eco=window.__eco||[]).push(a); return ok(null);
     case 'staff_marketing': return ok({videos:[{id:'v1',run_id:'gh-1',created_at:'2026-10-15T15:00:00Z',game:'boyblocks',video_path:'gh-1/video.mp4',poster_path:'gh-1/poster.jpg',duration:28,stats:{score:606,lignes:26,combo:6},accroche:'Satisfaisant jusqu au bout',legende:'606 points',hashtags:['#BOYGAMES','#puzzle'],text_source:'modèles',status:'a_valider',scheduled_for:null,posts:[]}],counts:{a_valider:1},settings:{auto:{enabled:false,per_day:1,platforms:['youtube','instagram','tiktok'],hour:18}},errors:[]});
     case 'staff_marketing_review': window.__mk=a; return ok(null);
     case 'economy_public': return ok({daily_streak:[5,5,10,10,15,15,40],game_bc_daily_cap:40});
     default: return ok(null);
    }
   }
  };
}};
