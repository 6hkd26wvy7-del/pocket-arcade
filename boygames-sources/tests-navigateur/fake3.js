window.__calls=[];
window.supabase = { createClient: function(){
  var me={pseudo:'Quentin',country:'FR',avatar:'av_01',featured_badge:null,xp:800,level:5,level_start_xp:800,next_level_xp:1250,bc:300,badges:['first_game','beta_founder'],items:[],streak:1,daily_claimed_today:true};
  var blocked=[]; var friends=[{pseudo:'Zoe',level:5,relation:'friend',avatar:'av_05',featured_badge:'beta_founder'},{pseudo:'Bob',level:3,relation:'incoming',avatar:'av_02',featured_badge:null}];
  var ok=function(d){return Promise.resolve({data:d,error:null})};
  var err=function(m){return Promise.resolve({data:null,error:{message:m}})};
  var tables={ badges:[{code:'first_game',name:'Premiers pas',description:'Termine ta première partie.',exclusive:false},{code:'beta_founder',name:'BÊTA TESTEUR — ÉDITION FONDATRICE',description:'Un des 10 premiers.',exclusive:true},{code:'founder',name:'FONDATEUR',description:'Le créateur.',exclusive:true}], news:[], shop_items:[] };
  return {
   auth:{ onAuthStateChange:function(fn){ fn('INITIAL_SESSION',{user:{id:'u1',email:'a@b.fr'}}); }, signOut:function(){return ok({})} },
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
     default: return ok(null);
    }
   }
  };
}};
