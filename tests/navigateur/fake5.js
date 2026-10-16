window.__calls=[];
window.supabase = { createClient: function(){
  var me={pseudo:'Quentin',country:'FR',avatar:'av_01',featured_badge:null,xp:800,level:5,level_start_xp:800,next_level_xp:1250,bc:300,badges:['first_game','beta_founder'],items:[],streak:1,daily_claimed_today:true};
  var blocked=[]; var friends=[{pseudo:'Zoe',level:5,relation:'friend',avatar:'av_05',featured_badge:'beta_founder'},{pseudo:'Bob',level:3,relation:'incoming',avatar:'av_02',featured_badge:null}];
  var ok=function(d){return Promise.resolve({data:d,error:null})};
  var err=function(m){return Promise.resolve({data:null,error:{message:m}})};
  var tables={ badges:[{code:'first_game',name:'Premiers pas',description:'Termine ta première partie.',exclusive:false},{code:'beta_founder',name:'BÊTA TESTEUR — ÉDITION FONDATRICE',description:'Un des 10 premiers.',exclusive:true},{code:'founder',name:'FONDATEUR',description:'Le créateur.',exclusive:true}], news:[], shop_items:[] };
  return {
   auth:{ onAuthStateChange:function(fn){ fn('INITIAL_SESSION',{user:{id:'u1',email:'a@b.fr'}}); }, signOut:function(){return ok({})}, getSession:function(){return ok({session:{access_token:'tok'}})} },
   from:function(t){ return { select:function(){ return { eq:function(){return {maybeSingle:function(){return ok({pseudo:'Quentin',country:'FR'})}}}, order:function(){ var r=ok(tables[t]||[]); r.limit=function(){return ok(tables[t]||[])}; return r; } }; } } },
   rpc:function(n,a){
    window.__calls.push(n+(a?JSON.stringify(a):''));
    switch(n){
     case 'boyblocks_start': window.__run={seed:424242}; return ok({run_id:'r1',seed:424242});
     case 'game_settings_public': return ok(window.__noNine ? {boyblocks9:{enabled:false}} : {boyblocks9:{enabled:true}});
     case 'boyblocks_start_v3': window.__run={seed:515151,rules:2,size:a.p_size}; return ok({run_id:'r9',seed:515151,rules:2,size:a.p_size});
     case 'boyblocks_start_v2': window.__run={seed:424242,rules:2}; return ok({run_id:'r1',seed:424242,rules:2});
     case 'boyblocks_finish': window.__fin=a; return ok({xp:12,bc:3,level:5,level_up:false,new_badges:[],score:1});
     case 'sync_tiers': if(window.__synced) return ok([]); window.__synced=1; return ok([{game:'snake',tier:1,name:'Argent'},{game:'boyblocks',tier:5,name:'Légende'}]);
     case 'my_tiers': return ok({favorites:window.__fav||['snake:1'],games:[{game:'blocks',best:122,plays:3,tier:null,next:{tier:0,name:'Recrue',min_score:300,min_plays:1}},{game:'boyblocks',best:41000,plays:410,tier:5,next:null},{game:'snake',best:136,plays:3,tier:1,next:{tier:2,name:'Or',min_score:60,min_plays:30}},{game:'space',best:108,plays:3,tier:null,next:{tier:0,name:'Recrue',min_score:200,min_plays:1}}]});
     case 'set_favorites': window.__fav=a.p_list; return ok(null);
     case 'public_tiers': return ok({favorites:['boyblocks:5','snake:1'],games:[]});
     case 'me': return ok(Object.assign({}, me, {premium: !!window.__premium, premium_until: window.__premium ? '2026-11-15T00:00:00Z' : null}));
     case 'monetization_public': return ok(window.__monet || {ads:{enabled:true,provider:'test',slots:{home:true,scores:true,shop:false}},rewarded:{enabled:true,continue_max:1,games:['snake','space']},premium:{enabled:true,price_eur:0.99,pioneer_limit:100,pioneer_left:99}});
     case 'rewarded_continue': return ok({ok:true,remaining_today:9,skip_ad:!!window.__premium});
     case 'submit_continued_score': window.__cont=a; return ok({xp:5,bc:0,level:5,level_up:false,ranked:false});
     case 'submit_score': window.__ranked=(window.__ranked||[]).concat([a]); return ok({xp:6,bc:2,level:5,level_up:false,new_badges:[]});
     case 'my_missions': return ok([]);
     case 'my_role': return ok(window.__role||null);
     case 'beta_survey_get': return ok(window.__survey||null);
     case 'beta_survey_save': window.__saves=(window.__saves||0)+1; window.__survey={answers:JSON.parse(JSON.stringify(a.p_answers)),comment:a.p_comment,completed_at:a.p_complete?new Date().toISOString():(window.__survey&&window.__survey.completed_at)||null}; return ok({ok:true,completed_at:window.__survey.completed_at});
     case 'staff_beta_survey': return ok(window.__staffRows||[]);
     case 'leaderboard': return ok([{rang:1,pseudo:'Zoe',score:120,moi:false},{rang:2,pseudo:'Max',score:90,moi:false},{rang:3,pseudo:'Quentin',score:40,moi:true}]);
     case 'beta_space': if(!window.__beta) window.__beta={version:1,codes:['compte','snake','boyblocks','space','multi','amis','boybot','classements','progression','mobile','questionnaire'],required:['compte','snake','boyblocks','space','multi','amis','boybot','classements','progression','mobile','questionnaire'],missions:{},evidence:{compte:true,snake:12,boyblocks:3,space:0,amis:1,classements:15,progression:{xp:800,niveau:5,bc:300,badges:2},questionnaire:false},eligible:false,badge:false,bugs:0}; return ok(JSON.parse(JSON.stringify(window.__beta)));
     case 'beta_mission_set': window.__beta.missions[a.p_code]={status:a.p_status,note:a.p_note}; return ok({ok:true,eligible:false});
     case 'staff_beta_overview': return ok(window.__overview||{version:1,codes:['compte','snake'],required:['compte','snake'],beta_on:false,testers:[]});
     case 'staff_beta_validate': window.__validated=a; return ok({ok:true,badge_added:true});
     case 'my_access': return ok(window.__access||null);
     case 'beta_redeem': window.__redeemed=(window.__redeemed||[]).concat([a.p_code]); if(String(a.p_code).replace(/[^A-Z0-9]/gi,'').toUpperCase()===(window.__goodCode||'AB12CD34')){ window.__access={beta_on:true,allowed:true}; return ok({ok:true,status:'joined'}); } return ok({ok:false,status:'invalid'});
     case 'staff_beta_invite_create': window.__invites=(window.__invites||[]).concat([{code:'K7P2Q9XZ',note:a.p_note,created_at:new Date().toISOString(),expires_at:new Date(Date.now()+a.p_days*864e5).toISOString(),max_uses:a.p_max_uses,uses:0,revoked:false,by:'Quentin',players:[]}]); return ok({code:'K7P2Q9XZ',expires_at:'',max_uses:a.p_max_uses});
     case 'staff_beta_invites': return ok(window.__invites||[]);
     case 'staff_beta_invite_revoke': return ok(null);
     case 'staff_beta_list': return ok(window.__betaList||[{pseudo:'Joh'}]);
     case 'staff_players': window.__playersCalls=(window.__playersCalls||0)+1; return ok(window.__players||[]);
     case 'staff_player_detail': window.__detailCalls=(window.__detailCalls||0)+1; return ok({profile:{pseudo:a.p_pseudo,avatar:'av_03',country:'FR',created_at:'2026-10-16T10:21:26Z'},account:{last_sign_in:'2026-10-16T10:21:12Z',confirmed:true},stats:{level:1,xp:0,bc:0},role:null,ban:window.__banned?{reason:'essai',since:'2026-10-16T12:00:00Z',until:null}:null,
       badges:[{code:'beta_founder',name:'BÊTA TESTEUR — ÉDITION FONDATRICE',exclusive:true,at:'2026-10-16T10:30:00Z'}],records:[],continued:0,friends:0,
       beta:{member:true,since:'2026-10-16T10:30:00Z',invite:null,version:1,codes:['compte','snake'],missions:{compte:{status:'reussi',note:''}},survey:null,survey_draft:false,eligible:false},
       reports_received:[{id:5,at:'2026-10-16T11:00:00Z',by:'Joh17',reason:'pseudo bizarre',status:'open'}],reports_sent:0,bugs:[],history:[{at:'2026-10-16T10:30:00Z',action:'beta_ajout',by:'tintintest',self:false,detail:{}}]});
     case 'staff_ban': window.__banned=a; return ok(null);
     case 'my_notifications': return ok([]);
     case 'get_maintenance': return ok({on:false,message:''});
     case 'my_friends': return ok(friends);
     case 'my_blocks': return ok(blocked.map(function(p){return {pseudo:p}}));
     case 'public_profile': return a.p_pseudo==='Max' ? ok({pseudo:'Max',avatar:'av_03',level:2,relation:'none',featured_badge:null,title:null,xp:null,games:null,badges:null}) : a.p_pseudo==='Zoe' ? ok({pseudo:'Zoe',avatar:'av_05',level:5,relation:'friend',featured_badge:{code:'beta_founder',name:'BÊTA TESTEUR — ÉDITION FONDATRICE'},title:{code:'title_legend',name:'LÉGENDE'},xp:900,games:[{game:'snake',best:42,plays:7},{game:'blocks',best:1200,plays:2}],badges:['beta_founder']} ) : ok({pseudo:a.p_pseudo,avatar:'av_02',level:3,relation:'pending',featured_badge:null,title:null,xp:null,games:null,badges:null});
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
