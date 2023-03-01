\set QUIET 1
\echo <!DOCTYPE html>
\echo <html><meta charset="utf-8" />
\echo <style>
\echo table, th, td { border: 1px solid black; border-collapse: collapse; padding: 2px 4px 2px 4px;}
\echo th {background-color: #d2f2ff;cursor: pointer; }
\echo tr:nth-child(even) {background-color: #eef8ff}
\echo tr:hover { background-color: #FFFFCA}
\echo h2 { scroll-margin-left: 2em;} /*keep the scroll left*/
\echo caption { font-size: larger }
\echo ol { width: fit-content;}
\echo .warn { font-weight:bold; background-color: #FAA }
\echo .high { border: 5px solid red;font-weight:bold}
\echo .lime { font-weight:bold}
\echo .lineblk {float: left; margin:0 9px 4px 0 }
\echo .bottomright { position: fixed; right: 0px; bottom: 0px; padding: 5px; border : 2px solid #AFAFFF; border-radius: 5px;}
\echo .thidden tr td:nth-child(2), .thidden th:nth-child(2) {display: none;}
\echo .thidden tr td:first-child {color:blue;}
\echo #cur { font: 5em arial; position: absolute; color:brown; animation: vanish 0.8s ease forwards; }  /*sort indicator*/
\echo #dtls,#finditem {position: absolute;background-color:#FAFFEA;border: 2px solid blue; border-radius: 5px; padding: 1em; box-shadow: 2px 2px grey;}
\echo @keyframes vanish { from { opacity: 1;} to {opacity: 0;} }
\echo summary {  padding: 1rem; font: bold 1.2em arial;  cursor: pointer } 
\echo footer { text-align: center; padding: 3px; background-color:#d2f2ff}
\echo </style>
\H
\pset footer off 
SET max_parallel_workers_per_gather = 0;

\echo <h1>
\echo   <svg width="10em" viewBox="0 0 140 80">
\echo     <path fill="none" stroke="#000000" stroke-linecap="round" stroke-width="2"  d="m 21.2,46.7 c 1,2 0.67,4 -0.3,5.1 c -1.1,1 -2,1.5 -4,1 c -10,-3 -4,-25 -4 -25 c 0.6,-10 8,-9 8 -9 s 7,-4.5 11,0.2 c 1.2,1.4 1.7,3.3 1.7,5.17 c -0.1,3 3,7 -2,10 c-2,2 -1,5 -8,5.5 m -2 -12 c 0,0 -1,1 -0.2,0.2 m -4 12 c 0,0 0,10 -12,11"/>
\echo     <text x="30" y="50" style="font:25px arial">gGather</text>
\echo     <text x="60" y="62" style="fill:red; font:15px arial">Report</text>
\echo    </svg>
\echo    <b id="busy" class="warn"> Loading... </b>
\echo </h1>
\pset tableattr 'class="lineblk"'
SELECT (SELECT count(*) > 1 FROM pg_srvr WHERE connstr ilike 'You%') AS conlines \gset
\if :conlines
  \echo "There is serious problem with the data. Please make sure that all tables are dropped and recreated as part of importing data (gather_schema.sql) and there was no error"
  "SOMETHING WENT WRONG WHILE IMPORTING THE DATA. PLEASE MAKE SURE THAT ALL TABLES ARE DROPPED AND RECREATED AS PART OF IMPORTING";
  \q
\endif
\set tzone `echo "$PG_GATHER_TIMEZONE"`
SELECT * FROM 
(WITH TZ AS (SELECT CASE WHEN :'tzone' = ''
    THEN (SELECT set_config('timezone',setting,false) FROM pg_get_confs WHERE name='log_timezone')
    ELSE  set_config('timezone',:'tzone',false) 
  END AS val)
SELECT  UNNEST(ARRAY ['Collected At','Collected By','PG build', 'PG Start','In recovery?','Client','Server','Last Reload','Current LSN']) AS pg_gather,
        UNNEST(ARRAY [CONCAT(collect_ts::text,' (',TZ.val,')'),usr,ver, pg_start_ts::text ||' ('|| collect_ts-pg_start_ts || ')',recovery::text,client::text,server::text,reload_ts::text,current_wal::text]) AS "Report-v19"
FROM pg_gather LEFT JOIN TZ ON TRUE 
UNION
SELECT  'Connection', replace(connstr,'You are connected to ','') FROM pg_srvr ) a WHERE "Report-v19" IS NOT NULL ORDER BY 1;
\pset tableattr 'id="dbs" class="thidden"'
WITH cts AS (SELECT COALESCE(collect_ts,(SELECT max(state_change) FROM pg_get_activity)) AS c_ts FROM pg_gather)
SELECT datname "DB Name",to_jsonb(ROW(tup_inserted/days,tup_updated/days,tup_deleted/days,to_char(stats_reset,'YYYY-MM-DD HH24-MI-SS')))
,xact_commit/days "Avg.Commits",xact_rollback/days "Avg.Rollbacks",(tup_inserted+tup_updated+tup_deleted)/days "Avg.DMLs", CASE WHEN blks_fetch > 0 THEN blks_hit*100/blks_fetch ELSE NULL END  "Cache hit ratio"
,temp_files/days "Avg.Temp Files",temp_bytes/days "Avg.Temp Bytes",db_size "DB size",age "Age"
FROM pg_get_db LEFT JOIN LATERAL (SELECT GREATEST((EXTRACT(epoch FROM(c_ts-stats_reset))/86400)::bigint,1) as days FROM cts) AS lat1 ON TRUE;
\pset tableattr off

\echo <div>
\echo <details style="clear: left; width: fit-content;">
\echo   <summary>Tune PostgreSQL Parameters (beta)</summary>
\echo   <label for="cpus">CPUs:
\echo   <input type="number" id="cpus" name="cpus" value="0">
\echo   </label>
\echo   <label for="mem" style="padding-left: 3em;">Memory(GB):
\echo   <input type="number" id="mem" name="mem" value="0">
\echo  </label>
\echo  <p style="border: 2px solid blue; border-radius: 5px; padding: 1em;">Please input the CPU and Memory available on the host machine for evaluating the current parameter settings<br />
\echo   Please see the tooltip against Parameters for recommendations based on calculations. Please seek expert advice</p>
\echo </details>
\echo </div>
\echo <h2 id="topics">Sections</h2>
\echo <ol>
\echo <li><a href="#tables">Tables</a></li>
\echo <li><a href="#indexes">Indexes</a></li>
\echo <li><a href="#parameters">Parameters / Settings</a></li>
\echo <li><a href="#extensions">Extensions</a></li>
\echo <li><a href="#activiy">Sessions Summary</a></li>
\echo <li><a href="#time">Database Time</a></li>
\echo <li><a href="#sess">Session Details</a></li>
\echo <li><a href="#blocking">Blocking Sessions</a></li>
\echo <li><a href="#statements" title="pg_get_statements">Top 10 Statements</a></li>
\echo <li><a href="#replstat">Replications</a></li>
\echo <li><a href="#bgcp" >BGWriter & Checkpointer</a></li>
\echo <li><a href="#findings">Findings</a></li>
\echo </ol>
\echo <div class="bottomright">
\echo   <a href="#topics">Sections (Alt+I)</a>
\echo </div>
\echo <div id="sections" style="display:none">
\echo <h2 id="tables">Tables</h2>
\echo <p><b>NOTE : Rel size</b> is the  main fork size, <b>Tot.Tab size</b> includes all forks and toast, <b>Tab+Ind size</b> is tot_tab_size + all indexes, *Bloat estimates are indicative numbers and they can be inaccurate<br />
\echo Objects other than tables will be marked with their relkind in brackets</p>
\pset footer on
\pset tableattr 'id="tabInfo" class="thidden"'
SELECT c.relname || CASE WHEN c.relkind != 'r' THEN ' ('||c.relkind||')' ELSE '' END "Name" ,
to_jsonb(ROW(r.n_tup_ins,r.n_tup_upd,r.n_tup_del,r.n_tup_hot_upd)),r.relnamespace "NS", CASE WHEN r.blks > 999 AND r.blks > tb.est_pages THEN (r.blks-tb.est_pages)*100/r.blks ELSE NULL END "Bloat%",
r.n_live_tup "Live tup",r.n_dead_tup "Dead tup", CASE WHEN r.n_live_tup <> 0 THEN  ROUND((r.n_dead_tup::real/r.n_live_tup::real)::numeric,4) END "Dead/Live",
r.rel_size "Rel size",r.tot_tab_size "Tot.Tab size",r.tab_ind_size "Tab+Ind size",r.rel_age,to_char(r.last_vac,'YYYY-MM-DD HH24:MI:SS') "Last vacuum",to_char(r.last_anlyze,'YYYY-MM-DD HH24:MI:SS') "Last analyze",r.vac_nos,
ct.relname "Toast name",rt.tab_ind_size "Toast+Ind" ,rt.rel_age "Toast Age",GREATEST(r.rel_age,rt.rel_age) "Max age"
FROM pg_get_rel r
JOIN pg_get_class c ON r.relid = c.reloid AND c.relkind NOT IN ('t','p')
LEFT JOIN pg_get_toast t ON r.relid = t.relid
LEFT JOIN pg_get_class ct ON t.toastid = ct.reloid
LEFT JOIN pg_get_rel rt ON rt.relid = t.toastid
LEFT JOIN pg_tab_bloat tb ON r.relid = tb.table_oid
LEFT JOIN pg_get_ns ns ON r.relnamespace = ns.nsoid
ORDER BY r.tab_ind_size DESC LIMIT 10000; 
\pset tableattr
\echo <h2 id="indexes">Indexes</h2>
\pset tableattr 'id="IndInfo"'
SELECT ct.relname AS "Table", ci.relname as "Index",indisunique as "UK?",indisprimary as "PK?",numscans as "Scans",size
  FROM pg_get_index i 
  JOIN pg_get_class ct on i.indrelid = ct.reloid and ct.relkind != 't'
  JOIN pg_get_class ci ON i.indexrelid = ci.reloid
ORDER BY size DESC LIMIT 10000;
\pset tableattr 
\echo <h2 id="parameters">Parameters & settings</h2>
\pset tableattr 'id="params"'
SELECT coalesce(s.name,f.name) "Name",s.setting,s.unit,s.source, 
string_agg(f.sourcefile ||' - '|| f.setting || CASE WHEN f.applied = true THEN ' (applicable)' ELSE '' END ,chr(10)) FILTER (WHERE s.source != f.sourcefile OR s.source IS NULL ) AS "Other locations"
FROM pg_get_confs s FULL OUTER JOIN pg_get_file_confs f ON lower(s.name) = lower(f.name)
GROUP BY 1,2,3,4 ORDER BY 1; 
\pset tableattr
\echo <h2 id="extensions">Extensions</h2>
SELECT ext.oid,extname,rolname as owner,extnamespace,extrelocatable,extversion FROM pg_get_extension ext
JOIN pg_get_roles on extowner=pg_get_roles.oid; 
\echo <h2 id="activiy">Session Summary</h2>
\pset footer off
\pset tableattr 'id="tblss"'
 SELECT d.datname,state,COUNT(pid) 
  FROM pg_get_activity a LEFT JOIN pg_get_db d on a.datid = d.datid
    WHERE state is not null GROUP BY 1,2 ORDER BY 1; 
\echo <h2 id="time">Database time</h2>
\pset tableattr 'id="tableConten" name="waits"'
\C 'Wait Events and CPU info.'
SELECT COALESCE(wait_event,'CPU') "Event", count(*)::text FROM pg_pid_wait
WHERE wait_event IS NULL OR wait_event NOT IN ('ArchiverMain','AutoVacuumMain','BgWriterHibernate','BgWriterMain','CheckpointerMain','LogicalApplyMain','LogicalLauncherMain','RecoveryWalStream','SysLoggerMain','WalReceiverMain','WalSenderMain','WalWriterMain','CheckpointWriteDelay','PgSleep')
GROUP BY 1 ORDER BY count(*) DESC;
\C

\echo <h2 id="sess" style="clear: both">Session Details</h2>
\pset tableattr 'id="tblsess"' 
SELECT * FROM (
  WITH w AS (SELECT pid,COALESCE(wait_event,'CPU') wait_event,count(*) cnt FROM pg_pid_wait GROUP BY 1,2 ORDER BY 1,2),
  g AS (SELECT MAX(state_change) as ts,MAX(GREATEST(backend_xid::text::bigint,backend_xmin::text::bigint)) mx_xid FROM pg_get_activity)
  SELECT a.pid,a.state, CASE query WHEN '' THEN '**'||backend_type||' process**' ELSE query END "Last statement", g.ts - backend_start "Connection Since", g.ts - xact_start "Transaction Since", g.mx_xid - backend_xmin::text::bigint "xmin age",
   g.ts - query_start "Statement since",g.ts - state_change "State since", string_agg( w.wait_event ||':'|| w.cnt,',') waits 
  FROM pg_get_activity a 
   LEFT JOIN w ON a.pid = w.pid
   LEFT JOIN (SELECT pid,sum(cnt) tot FROM w GROUP BY 1) s ON a.pid = s.pid
   LEFT JOIN g ON true
  GROUP BY 1,2,3,4,5,6,7,8 ORDER BY 6 DESC NULLS LAST) AS sess
WHERE waits IS NOT NULL OR state != 'idle'; 
\echo <h2 id="blocking" style="clear: both">Blocking Sessions</h2>
\pset tableattr 'id="tblblk"'
SELECT * FROM pg_get_block; 
\echo <h2 id="statements" style="clear: both">Top 10 Statements</h2>
\pset tableattr 'id="tblstmnt"'
\C 'Statements consuming highest database time. Consider information from pg_get_statements for other criteria'
select query,total_time,calls from pg_get_statements order by 2 desc limit 10; 
\C 
\echo <h2 id="replstat" style="clear: both">Replication Status</h2>
\pset tableattr 'id="tblreplstat"'
WITH M AS (SELECT GREATEST((SELECT(current_wal) FROM pg_gather),(SELECT MAX(sent_lsn) FROM pg_replication_stat))),
  g AS (SELECT MAX(GREATEST(backend_xid::text::bigint,backend_xmin::text::bigint)) mx_xid FROM pg_get_activity)
SELECT usename AS "Replication User",client_addr AS "Replica Address",pid,state,
 pg_wal_lsn_diff(M.greatest, sent_lsn) "Transmission Lag (Bytes)",pg_wal_lsn_diff(sent_lsn,write_lsn) "Replica Write lag(Bytes)",
 pg_wal_lsn_diff(write_lsn,flush_lsn) "Replica Flush lag(Bytes)",pg_wal_lsn_diff(flush_lsn,replay_lsn) "Replay at Replica lag(Bytes)",
 slot_name "Slot",plugin,slot_type "Type",datname "DB name",temporary,active,GREATEST(g.mx_xid-old_xmin::text::bigint,0) as "xmin age",
 GREATEST(g.mx_xid-catalog_xmin::text::bigint,0) as "catalog xmin age", GREATEST(pg_wal_lsn_diff(M.greatest,restart_lsn),0) as "Restart LSN lag(Bytes)",
 GREATEST(pg_wal_lsn_diff(M.greatest,confirmed_flush_lsn),0) as "Confirmed LSN lag(Bytes)"
FROM pg_replication_stat JOIN M ON TRUE
  FULL OUTER JOIN pg_get_slots s ON pid = active_pid
  LEFT JOIN g ON TRUE
  LEFT JOIN pg_get_db ON s.datoid = datid;

\echo <h2 id="bgcp" style="clear: both">Background Writer and Checkpointer Information</h2>
\echo <p>Efficiency of Background writer and Checkpointer Process</p>
\pset tableattr 'id="tblchkpnt"'
SELECT round(checkpoints_req*100/tot_cp,1) "Forced Checkpoint %" ,
round(min_since_reset/tot_cp,2) "avg mins between CP",
round(checkpoint_write_time::numeric/(tot_cp*1000),4) "Avg CP write time (s)",
round(checkpoint_sync_time::numeric/(tot_cp*1000),4)  "Avg CP sync time (s)",
round(total_buffers::numeric*8192/(1024*1024),2) "Tot MB Written",
round((buffers_checkpoint::numeric/tot_cp)*8192/(1024*1024),4) "MB per CP",
round(buffers_checkpoint::numeric*8192/(min_since_reset*60*1024*1024),4) "Checkpoint MBps",
round(buffers_clean::numeric*8192/(min_since_reset*60*1024*1024),4) "Bgwriter MBps",
round(buffers_backend::numeric*8192/(min_since_reset*60*1024*1024),4) "Backend MBps",
round(total_buffers::numeric*8192/(min_since_reset*60*1024*1024),4) "Total MBps",
round(buffers_alloc::numeric/total_buffers,3)  "New buffers ratio",
round(100.0*buffers_checkpoint/total_buffers,1)  "Clean by checkpoints (%)",
round(100.0*buffers_clean/total_buffers,1)   "Clean by bgwriter (%)",
round(100.0*buffers_backend/total_buffers,1)  "Clean by backends (%)",
round(100.0*maxwritten_clean/(min_since_reset*60000 / delay.setting::numeric),2)   "Bgwriter halts (%) per runs (**1)",
coalesce(round(100.0*maxwritten_clean/(nullif(buffers_clean,0)/ lru.setting::numeric),2),0)  "Bgwriter halt (%) due to LRU hit (**2)",
round(min_since_reset/(60*24),1) "Reset days"
FROM pg_get_bgwriter
CROSS JOIN 
(SELECT 
    round(extract('epoch' from (select collect_ts from pg_gather) - stats_reset)/60)::numeric min_since_reset,
    GREATEST(buffers_checkpoint + buffers_clean + buffers_backend,1) total_buffers,
    checkpoints_timed+checkpoints_req tot_cp 
    FROM pg_get_bgwriter) AS bg
LEFT JOIN pg_get_confs delay ON delay.name = 'bgwriter_delay'
LEFT JOIN pg_get_confs lru ON lru.name = 'bgwriter_lru_maxpages'; 
\echo <p>**1 What percentage of bgwriter runs results in a halt, **2 What percentage of bgwriter halts are due to hitting on <code>bgwriter_lru_maxpages</code> limit</p>
\echo <h2 id="findings" >Findings</h2>
\echo <ol id="finditem" style="padding:2em;position:relative">
\pset format aligned
\pset tuples_only on
WITH W AS (SELECT COUNT(*) AS val FROM pg_get_activity WHERE state='idle in transaction')
SELECT CASE WHEN val > 0 
  THEN '<li>There are '||val||' idle in transaction session(s) </li>' 
  ELSE NULL END 
FROM W; 
WITH W AS (SELECT count(*) AS val from pg_get_rel r JOIN pg_get_class c ON r.relid = c.reloid AND c.relkind NOT IN ('t','p'))
SELECT CASE WHEN val > 10000
  THEN '<li>There are <b>'||val||' tables!</b> in this database, Only the biggest 10000 will be listed in this report under <a href= "#tabInfo" >Tables Info</a>. Please use query No. 10. from the analysis_quries.sql for full details </li>'
  ELSE NULL END
FROM W;
WITH W AS (select last_failed_time,last_archived_time,last_archived_wal from pg_archiver_stat where last_archived_time < last_failed_time)
SELECT CASE WHEN last_archived_time IS NOT NULL
  THEN '<li>WAL archiving is failing since <b>'||last_archived_time||' (duration:'|| (SELECT COALESCE(collect_ts,(SELECT max(state_change) FROM pg_get_activity)) AS c_ts FROM pg_gather) - last_archived_time  ||') onwards</b> '  ||
  COALESCE(
  (SELECT ' With estimated size <b>' ||
  pg_size_pretty(((('x'||lpad(split_part(current_wal::TEXT,'/', 1),8,'0'))::bit(32)::bigint - ('x'||substring(last_archived_wal,9,8))::bit(32)::bigint) * 255 * 16^6 + 
  ('x'||lpad(split_part(current_wal::TEXT,'/', 2),8,'0'))::bit(32)::bigint - ('x'||substring(last_archived_wal,17,8))::bit(32)::bigint*16^6 )::bigint)
  FROM pg_gather), ' ') || '</b> behind </li>'
ELSE NULL END
FROM W;
WITH W AS (select count(*) AS val from pg_get_index i join pg_get_class ct on i.indrelid = ct.reloid and ct.relkind != 't')
SELECT CASE WHEN val > 10000
  THEN '<li>There are <b>'||val||' indexes!</b> in this database, Only biggest 10000 will be listed in this report under <a href= "#indexes" >Index Info</a>. Please use query No. 11. from the analysis_quries.sql for full details </li>'
  ELSE NULL END
FROM W;
WITH W AS (
 select string_agg(name ||'='||setting,',') as val FROM pg_get_confs WHERE 
 name in ('block_size','max_identifier_length','max_function_args','max_index_keys','segment_size','wal_block_size') AND 
 (name,setting) NOT IN (('block_size','8192'),('max_identifier_length','63'),('max_function_args','100'),('max_index_keys','32'),('segment_size','131072'),('wal_block_size','8192'))
 OR (name = 'wal_segment_size' AND unit ='8kB' and setting != '2048') OR (name = 'wal_segment_size' AND unit ='B' and setting != '16777216')  
)
SELECT CASE WHEN LENGTH(val) > 1
  THEN '<li>Detected Non-Standard Compile-time parameter changes <b>'||val||' </b>. Custom Compilation prone to bugs and it is beyond supportability</li>'
  ELSE NULL END
FROM W;
WITH W AS (
SELECT count(*) cnt FROM pg_get_confs WHERE source IS NOT NULL )
SELECT CASE WHEN cnt < 1
  THEN '<li>Couldn''t get parameter values. Partial gather or corrupt Parameter file(s)</li>'
  ELSE NULL END
FROM W;
SELECT 'ERROR :'||error ||': '||name||' with setting '||setting||' in '||sourcefile FROM pg_get_file_confs WHERE error IS NOT NULL;

\echo </ol>
\echo <div id="analdata" hidden>
\pset format unaligned
SELECT to_jsonb(r) FROM
(SELECT 
  (select recovery from pg_gather) AS clsr,
  (SELECT to_jsonb(ROW(count(*),COUNT(*) FILTER (WHERE last_vac IS NULL),COUNT(*) FILTER (WHERE last_anlyze IS NULL))) 
     from pg_get_rel r JOIN pg_get_class c ON r.relid = c.reloid AND c.relkind NOT IN ('t','p')) AS tabs,
  (SELECT to_jsonb(ROW(COUNT(*),COUNT(*) FILTER (WHERE CONN < interval '15 minutes' ) )) FROM 
    (WITH g AS (SELECT MAX(state_change) as ts FROM pg_get_activity)
    SELECT pid,g.ts - backend_start CONN
    FROM pg_get_activity
    LEFT JOIN g ON true
    WHERE EXISTS (SELECT pid FROM pg_pid_wait WHERE pid=pg_get_activity.pid)
    AND backend_type='client backend') cn) AS cn,
  (select count(*) from pg_get_class where relkind='p') as ptabs,
  (SELECT  to_jsonb(ROW(count(*) FILTER (WHERE state='active' AND state IS NOT NULL), 
   count(*) FILTER (WHERE state='idle in transaction'), count(*) FILTER (WHERE state='idle'),
   count(*) FILTER (WHERE state IS NULL), count(*) FILTER (WHERE leader_pid IS NOT NULL) , count(*)))
   FROM pg_get_activity) as sess,
  (WITH curdb AS (SELECT trim(both '\"' from substring(connstr from '\"\w*\"')) "curdb" FROM pg_srvr WHERE connstr like '%to database%'),
    cts AS (SELECT COALESCE((SELECT COALESCE(collect_ts,(SELECT max(state_change) FROM pg_get_activity)) FROM pg_gather),current_timestamp) AS c_ts)
    SELECT to_jsonb(ROW(curdb,stats_reset,c_ts,days)) FROM 
    curdb LEFT JOIN pg_get_db ON pg_get_db.datname=curdb.curdb
    LEFT JOIN LATERAL (SELECT GREATEST((EXTRACT(epoch FROM(c_ts-stats_reset))/86400)::bigint,1) as days FROM cts) AS lat1 ON TRUE
    LEFT JOIN cts ON true) as dbts,
  (SELECT json_agg(pg_get_ns) FROM  pg_get_ns WHERE nsoid > 16384 OR nsname='public') AS ns,
  (SELECT to_jsonb((collect_ts-last_failed_time) < '5 minute' :: interval) FROM pg_gather,pg_archiver_stat) AS arcfail,
  (SELECT to_jsonb(setting) FROM pg_get_confs WHERE name = 'archive_library') AS arclib,
  (SELECT CASE WHEN max(stats_reset)-min(stats_reset) < '2 minute' :: interval THEN min(stats_reset) ELSE NULL END 
  FROM (SELECT stats_reset FROM pg_get_db UNION SELECT stats_reset FROM pg_get_bgwriter) reset) crash,
  (WITH blockers AS (select array_agg(victim_pid) OVER () victim,blocking_pids blocker from pg_get_pidblock),
   ublokers as (SELECT unnest(blocker) AS blkr FROM blockers)
   SELECT json_agg(blkr) FROM ublokers
   WHERE NOT EXISTS (SELECT 1 FROM blockers WHERE ublokers.blkr = ANY(victim))) blkrs,
  (select json_agg((victim_pid,blocking_pids)) from pg_get_pidblock) victims,
  (select to_jsonb((EXTRACT(epoch FROM (end_ts-collect_ts)),pg_wal_lsn_diff(end_lsn,current_wal)*60*60/EXTRACT(epoch FROM (end_ts-collect_ts)))) 
  from pg_gather,pg_gather_end) sumry,
  (SELECT json_agg((relname,maint_work_mem_gb)) FROM (SELECT relname,n_live_tup*0.2*6 maint_work_mem_gb 
   FROM pg_get_rel JOIN pg_get_class ON n_live_tup > 894784853 AND pg_get_rel.relid = pg_get_class.reloid 
   ORDER BY 2 DESC LIMIT 3) AS wmemuse) wmemuse
) r;

\echo </div>
\echo </div> <!--End of "sections"-->
\echo <script type="text/javascript">
\echo obj={};
\echo meta={pgvers:["11.19","12.14","13.10","14.7","15.2"]};
\echo mgrver="";
\echo walcomprz="";
\echo autovacuum_freeze_max_age = 0;
\echo totdb=0;
\echo totCPU=0;
\echo totMem=0;
\echo let blokers = []
\echo let blkvictims = []
\echo document.addEventListener("DOMContentLoaded", () => {
\echo obj=JSON.parse( document.getElementById("analdata").innerText);
\echo if (obj.victims !== null){
\echo obj.victims.forEach(function(victim){
\echo   blkvictims.push(victim.f1);
\echo });
\echo obj.victims.forEach(function(victim){
\echo   victim.f2.forEach(function(blker){
\echo     if (blkvictims.indexOf(blker) == -1 && blokers.indexOf(blker) == -1) blokers.push(blker);
\echo   });
\echo });
\echo }
\echo checkpars();
\echo checktabs();
\echo checkdbs();
\echo checksess();
\echo checkfindings();
\echo });
\echo window.onload = function() {
\echo   ["tabInfo","IndInfo","params","sections"].forEach(function(t) {document.getElementById(t).style="display:table";})
\echo   document.getElementById("sections").style="display:table";
\echo   document.getElementById("busy").style="display:none";
\echo };
\echo function checkfindings(){
\echo   let strfind = "";
\echo   if (obj.cn.f1 > 0){
\echo     strfind="<li><b>" + obj.cn.f2 + " / " + obj.cn.f1 + " connections </b> in use are new. "
\echo     if (obj.cn.f2 > 9 || obj.cn.f2/obj.cn.f1 > 0.7 ){
\echo       strfind+="Please consider this for improving connection pooling"
\echo     } 
\echo     strfind += "</li>";
\echo   }
\echo   if (obj.ptabs > 0) strfind += "<li>"+ obj.ptabs +" Natively partitioned tables found. Tables section could contain partitions</li>";
\echo  if(obj.clsr){
\echo   strfind += "<li>PostgreSQL is in Standby mode or in Recovery</li>";
\echo  }else{
\echo   if ( obj.tabs.f2 > 0 ) strfind += "<li> <b>No vaccum info for " + obj.tabs.f2 + "</b> tables </li>";
\echo   if ( obj.tabs.f3 > 0 ) strfind += "<li> <b>No statistics available for " + obj.tabs.f3 + " tables</b>, query planning can go wrong </li>";
\echo   if ( obj.tabs.f1 > 10000) strfind += "<li> There are <b>" + obj.tabs.f1 + " tables</b> in the database. Only 10000 will be displayed in the report. Avoid too many tables in single database</li>";
\echo   if (obj.arcfail) strfind += "<li>WAL archiving is suspected to be <b>failing</b>, please check PG logs</li>";
\echo   if (obj.crash) strfind += "<li><b>Crash detected around "+ obj.crash +"</b>, please check PG logs</li>";
\echo   if (obj.wmemuse !== null && obj.wmemuse.length > 0){ strfind += "<li> Biggest <code>maintenance_work_mem</code> consumers are :<b>"; obj.wmemuse.forEach(function(t,idx){ strfind += (idx+1)+". "+t.f1 + " (" + bytesToSize(t.f2) + ")    " }); strfind += "</b></li>"; }
\echo   if (obj.victims !== null && obj.victims.length > 0) strfind += "<li>There are <b>" + obj.victims.length + " sessions blocked.</b></li>"
\echo   if (obj.sumry !== null){ strfind += "<li>Data collection took <b>" + obj.sumry.f1 + " seconds. </b>";
\echo      if ( obj.sumry.f1 < 23 ) strfind += "System response is good</li>";
\echo      else if ( obj.sumry.f1 < 28 ) strfind += "System response is below average</li>";
\echo      else strfind += "System response appears to be poor</li>";
\echo      strfind += "<li>Current WAL generation rate is <b>" + bytesToSize(obj.sumry.f2) + " / hour</b></li>"; }
\echo   if ( mgrver < Math.trunc(meta.pgvers[0])) strfind += "<li>PostgreSQL <b>Version : " + mgrver + " is outdated (EOL) and not supported</b>, Please upgrade urgently</li>";
\echo   if ( mgrver >= 15 && ( walcomprz == "off" || walcomprz == "on")) strfind += "<li>The <b>wal_compression is '" + walcomprz + "' on PG"+ mgrver +"</b>, consider a good compression method (lz4,zstd)</li>"
\echo   if (obj.ns !== null){
\echo    let tempNScnt = obj.ns.filter(n => n.nsname.indexOf("pg_temp") > -1).length + obj.ns.filter(n => n.nsname.indexOf("pg_toast_temp") > -1).length ;
\echo    strfind += "<li> There are <b>" + (obj.ns.length - tempNScnt).toString()  + " user schemas and " + tempNScnt + " temporary schema</b> in this database.</li>";
\echo   }
\echo   document.getElementById("finditem").innerHTML += strfind;
\echo  }
\echo   var el=document.createElement("tfoot");
\echo   el.innerHTML = "<th colspan='9'>**Averages are Per Day. Total size of "+ (document.getElementById("dbs").tBodies[0].rows.length - 1) +" DBs : "+ bytesToSize(totdb) +"</th>";
\echo   dbs=document.getElementById("dbs");
\echo   dbs.appendChild(el);
\echo   el=document.createElement("tfoot");
\echo   el.innerHTML = "<th colspan='3'>Active: "+ obj.sess.f1 +", Idle-in-transaction: " + obj.sess.f2 + ", Idle: " + obj.sess.f3 + ", Background: " + obj.sess.f4 + ", Workers: " + obj.sess.f5 + ", Total: " + obj.sess.f6 + "</th>";
\echo   tblss=document.getElementById("tblss");
\echo   tblss.appendChild(el);
\echo }
\echo document.getElementById("cpus").addEventListener("change", (event) => {
\echo   totCPU = event.target.value;
\echo   checkpars();
\echo });
\echo document.getElementById("mem").addEventListener("change", (event) => {
\echo   totMem = event.target.value;
\echo   checkpars();
\echo });
\echo function bytesToSize(bytes,divisor = 1000) {
\echo   const sizes = ["B","KB","MB","GB","TB"];
\echo   if (bytes == 0) return "0B";
\echo   const i = parseInt(Math.floor(Math.log(bytes) / Math.log(divisor)), 10);
\echo   if (i === 0) return bytes + sizes[i];
\echo   return (bytes / (divisor ** i)).toFixed(1) + sizes[i]; 
\echo }
\echo function DurationtoSeconds(duration){
\echo     const [hours, minutes, seconds] = duration.split(":");
\echo     return Number(hours) * 60 * 60 + Number(minutes) * 60 + Number(seconds);
\echo };
\echo function checkpars(){
\echo   const startTime =new Date().getTime();
\echo   trs=document.getElementById("params").rows
\echo   for(var i=1;i<trs.length;i++){
\echo     tr=trs[i]; nm=tr.cells[0]; val=tr.cells[1];
\echo     switch(nm.innerText){
\echo       case "archive_command" :
\echo         if (obj.arclib !== null && obj.arclib.length > 0) { val.classList.add("warn"); val.title="archive_command won't be in-effect, because archive_library : " + obj.arclib + " is specified"  }
\echo         break;
\echo       case "autovacuum" :
\echo         if(val.innerText != "on") { val.classList.add("warn"); val.title="Autovacuum must be on" }
\echo         break;
\echo       case "autovacuum_max_workers" :
\echo         if(val.innerText > 3) { val.classList.add("warn"); val.title="Worker slows down as the number of workers increases" }
\echo         break;
\echo       case "autovacuum_vacuum_cost_limit" :
\echo         if(val.innerText > 800 || val.innerText == -1 ) { val.classList.add("warn"); val.title="Consider a value less than 800" }
\echo         break;
\echo       case "autovacuum_freeze_max_age" :
\echo         autovacuum_freeze_max_age = Number(val.innerText);
\echo         if (autovacuum_freeze_max_age > 800000000) val.classList.add("warn");
\echo         break;
\echo       case "checkpoint_timeout":
\echo         if(val.innerText < 1200) { val.classList.add("warn"); val.title="Too small gap between checkpoints"}
\echo         break;
\echo       case "deadlock_timeout":
\echo         val.classList.add("lime");
\echo         break;
\echo       case "effective_cache_size":
\echo         val.classList.add("lime"); val.title=bytesToSize(val.innerText*8192,1024);
\echo         break;
\echo       case "huge_pages":
\echo         val.classList.add("lime");
\echo         break;
\echo       case "huge_page_size":
\echo         val.classList.add("lime");
\echo         break;
\echo       case "hot_standby_feedback":
\echo         val.classList.add("lime");
\echo         break;
\echo       case "jit":
\echo         if (val.innerText=="on") { val.classList.add("warn"); val.title="JIT is reportedly causing high memory usage and even crashes in few cases. consider disabling it unless needed" }
\echo         break;
\echo       case "maintenance_work_mem":
\echo         val.classList.add("lime"); val.title=bytesToSize(val.innerText*1024,1024);
\echo         break;
\echo       case "shared_buffers":
\echo         val.classList.add("lime"); val.title=bytesToSize(val.innerText*8192,1024);
\echo         if( totMem > 0 && ( totMem < val.innerText*8*0.2/1048576 || totMem > val.innerText*8*0.3/1048576 ))
\echo           { val.classList.add("warn"); val.title="Approx. 25% of available memory is recommended, current value of " + bytesToSize(val.innerText*8192,1024) + " appears to be off" }
\echo         break;
\echo       case "max_connections":
\echo         val.title="Avoid value exceeding 10x of the CPUs"
\echo         if( totCPU > 0 ){
\echo           if(val.innerText > 10 * totCPU) { val.classList.add("warn"); val.title="If there is only " + totCPU + " CPUs value above " + 10*totCPU + " Is not recommendable for performance and stability" }
\echo           else { val.classList.remove("warn"); val.classList.add("lime"); val.title="Current value is good" }
\echo         } else if (val.innerText > 500) val.classList.add("warn")
\echo         else val.classList.add("lime")
\echo         break;
\echo       case "max_wal_size":
\echo         val.classList.add("lime"); val.title=bytesToSize(val.innerText*1024*1024,1024);
\echo         if(val.innerText < 10240) val.classList.add("warn");
\echo         break;
\echo       case "random_page_cost":
\echo         if(val.innerText > 1.2) val.classList.add("warn");
\echo         break;
\echo       case "server_version":
\echo         val.classList.add("lime"); let setval = val.innerText.split(" ")[0]; mgrver=setval.split(".")[0];
\echo         if ( mgrver < Math.trunc(meta.pgvers[0])){
\echo           val.classList.add("warn"); val.title="PostgreSQL Version is outdated (EOL) and not supported";
\echo         } else {
\echo           meta.pgvers.forEach(function(t){
\echo             if (Math.trunc(setval) == Math.trunc(t)){
\echo                if (t.split(".")[1] - setval.split(".")[1] > 0 ) { val.classList.add("warn"); val.title= t.split(".")[1] - setval.split(".")[1] + " minor version updates pending. Urgent!"; }
\echo             }
\echo           })  
\echo         }
\echo         break;
\echo       case "synchronous_standby_names":
\echo         if (val.innerText.trim().length > 0){ val.classList.add("warn"); val.title="Synchronous Standby can cause session hangs, and poor performance"; }
\echo         break;
\echo       case "wal_compression":
\echo         val.classList.add("lime");
\echo         walcomprz = val.innerText;
\echo         break;
\echo       case "work_mem":
\echo         val.classList.add("lime"); val.title=bytesToSize(val.innerText*1024,1024);
\echo         if(val.innerText > 98304) val.classList.add("warn");
\echo         break;
\echo     }
\echo   }
\echo const endTime = new Date().getTime();
\echo console.log("time taken :" + (endTime - startTime));
\echo }
\echo function aged(cell){
\echo  if(cell.innerHTML > autovacuum_freeze_max_age){ cell.classList.add("warn"); cell.title =  Number(cell.innerText).toLocaleString("en-US"); }
\echo }
\echo function checktabs(){
\echo   const startTime =new Date().getTime();
\echo   const trs=document.getElementById("tabInfo").rows
\echo   const len=trs.length;
\echo   trs[0].cells[2].title="Namespace / Schema oid";trs[0].cells[3].title="Bloat in Percentage";
\echo   [10,16,17].forEach(function(num){trs[0].cells[num].title="autovacuum_freeze_max_age=" + autovacuum_freeze_max_age.toLocaleString("en-US")})
\echo   for(var i=1;i<len;i++){
\echo     tr=trs[i]; let TotTab=tr.cells[8]; TotTabSize=Number(TotTab.innerHTML); TabInd=tr.cells[9]; TabIndSize=(TabInd.innerHTML);
\echo     if(TotTabSize > 5000000000 ) { TotTab.classList.add("lime"); TotTab.title = bytesToSize(TotTabSize) + "\nBig Table, Consider Partitioning, Archive+Purge"; 
\echo     } else TotTab.title=bytesToSize(TotTabSize);
\echo     if( TabIndSize > 2*TotTabSize && TotTabSize > 2000000 ){ TabInd.classList.add("warn"); TabInd.title="Indexes of : " + bytesToSize(TabIndSize-TotTabSize) + " is " + ((TabIndSize-TotTabSize)/TotTabSize).toFixed(2) + "x of Table " + bytesToSize(TotTabSize) + "\n Total : " + bytesToSize(TabIndSize)
\echo     } else TabInd.title=bytesToSize(TabIndSize); 
\echo     if (TabIndSize > 10000000000) TabInd.classList.add("lime");
\echo     if (tr.cells[13].innerText / obj.dbts.f4 > 12) tr.cells[13].classList.add("warn");  tr.cells[13].title="Too frequent vacuum runs : " + Math.round(tr.cells[13].innerText / obj.dbts.f4) + "/day";
\echo     if (tr.cells[15].innerText > 10000) { 
\echo       tr.cells[15].title=bytesToSize(Number(tr.cells[15].innerText)); 
\echo       if (tr.cells[15].innerText > 10737418240) tr.cells[15].classList.add("warn")
\echo       else tr.cells[15].classList.add("lime")
\echo     }
\echo     aged(tr.cells[10]);
\echo     aged(tr.cells[16]);
\echo     aged(tr.cells[17]);
\echo   }
\echo const endTime = new Date().getTime();
\echo console.log("time taken for checktabs :" + (endTime - startTime));
\echo }
\echo function checkdbs(){
\echo   const trs=document.getElementById("dbs").rows
\echo   const len=trs.length;
\echo   trs[0].cells[6].title="Average Temp generation Per Day"; trs[0].cells[7].title="Average Temp generation Per Day"; trs[0].cells[9].title="autovacuum_freeze_max_age=" + autovacuum_freeze_max_age.toLocaleString("en-US");
\echo   for(var i=1;i<len;i++){
\echo     tr=trs[i];
\echo     if(obj.dbts !== null && tr.cells[0].innerHTML == obj.dbts.f1) tr.cells[0].classList.add("lime");
\echo     [7,8].forEach(function(num) {  if (tr.cells[num].innerText > 1048576) { tr.cells[num].classList.add("lime"); tr.cells[num].title=bytesToSize(tr.cells[num].innerText) } });
\echo     if(tr.cells[7].innerHTML > 50000000000) tr.cells[7].classList.add("warn");
\echo     totdb=totdb+Number(tr.cells[8].innerText);
\echo     aged(tr.cells[9]);
\echo   }  
\echo }
\echo const getCellValue = (tr, idx) => tr.children[idx].innerText || tr.children[idx].textContent;
\echo const comparer = (idx, asc) => (a, b) => ((v1, v2) =>   v1 !== '''''' && v2 !== '''''' && !isNaN(v1) && !isNaN(v2) ? v1 - v2 : v1.toString().localeCompare(v2))(getCellValue(asc ? a : b, idx), getCellValue(asc ? b : a, idx));
\echo document.querySelectorAll(''''th'''').forEach(th => th.addEventListener(''''click'''', (() => {
\echo   const table = th.closest(''''table'''');
\echo   th.style.cursor = "progress";
\echo   var el=document.createElement("div");
\echo   el.setAttribute("id", "cur");
\echo   if (this.asc) el.textContent = "⬆";
\echo   else el.textContent = "⬇";
\echo   th.appendChild(el);
\echo   setTimeout(() => { el.remove();},1000);
\echo   setTimeout(function (){
\echo   Array.from(table.querySelectorAll(''''tr:nth-child(n+2)'''')).sort(comparer(Array.from(th.parentNode.children).indexOf(th), this.asc = !this.asc)).forEach(tr => table.appendChild(tr) );
\echo   setTimeout(function(){th.style.cursor = "pointer";},10);
\echo   },50);
\echo })));
\echo function dbsdtls(th){
\echo   let o=JSON.parse(th.cells[1].innerText);
\echo   let str="";
\echo   if(th.cells[0].classList.contains("lime")) str = "<br/>(pg_gather connected)";
\echo   return "<b>" + th.cells[0].innerText + "</b>" + str + "<br/> Inserts per day : " + o.f1 + "<br/>Updates per day : " + o.f2 + "<br/>Deletes per day : " + o.f3 + "<br/>Stats Reset : " + o.f4 ;
\echo }
\echo function tabdtls(th){
\echo   let o=JSON.parse(th.cells[1].innerText);
\echo   let vac=th.cells[13].innerText;
\echo   let ns=obj.ns.find(el => el.nsoid === JSON.parse(th.cells[2].innerText).toString());
\echo   let str=""
\echo   if (obj.dbts.f4 < 1) obj.dbts.f4 = 1;
\echo   if (vac > 0) str="<br />Vacuums / day : " + Number(vac/obj.dbts.f4).toFixed(1);
\echo   str += "<br/>Inserts / day : " + Math.round(o.f1/obj.dbts.f4);
\echo   str += "<br/>Updates / day : " + Math.round(o.f2/obj.dbts.f4);
\echo   str += "<br/>Deletes / day : " + Math.round(o.f3/obj.dbts.f4);
\echo   str += "<br/>HOT.updates / day : " + Math.round(o.f4/obj.dbts.f4);
\echo   if (o.f2 > 0) str += "<br/>FILLFACTOR recommendation :" + Math.round(100 - 20*o.f2/(o.f2+o.f1)+ 20*o.f2*o.f4/((o.f2+o.f1)*o.f2));
\echo   if (vac/obj.dbts.f4 > 50) { 
\echo     let threshold = Math.round((Math.round(o.f2/obj.dbts.f4) + Math.round(o.f3/obj.dbts.f4))/48);
\echo     if (threshold < 500) threshold = 500;
\echo     str += "<br/>AUTOVACUUM recommendation : autovacuum_vacuum_threshold = "+ threshold +", autovacuum_analyze_threshold = " + threshold
\echo   }
\echo   return "<b>" + th.cells[0].innerText + "</b><br/>Schema : " + ns.nsname + str;
\echo }
\echo document.querySelectorAll(".thidden tr td:first-child").forEach(td => td.addEventListener("mouseover", (() => {
\echo   th=td.parentNode;
\echo   tab=th.closest("table");
\echo   var el=document.createElement("div");
\echo   el.setAttribute("id", "dtls");
\echo   el.setAttribute("align","left");
\echo   if(tab.id=="dbs") el.innerHTML=dbsdtls(th);
\echo   if(tab.id=="tabInfo") el.innerHTML=tabdtls(th);
\echo   th.cells[2].appendChild(el);
\echo })));
\echo document.querySelectorAll(".thidden tr td:first-child").forEach(td => td.addEventListener("mouseout", (() => {
\echo   td.parentNode.cells[2].innerHTML=td.parentNode.cells[2].firstChild.textContent;
\echo })));
\echo document.querySelectorAll("#tblsess tr td:nth-child(3)").forEach(td => td.addEventListener("click", (() => {
\echo   console.log(td.title);
\echo })));
\echo trs=document.getElementById("IndInfo").rows;
\echo for (let tr of trs) {
\echo   if(tr.cells[4].innerText == 0) {tr.cells[4].classList.add("warn"); tr.cells[4].title="Unused Index"}
\echo   tr.cells[5].title=bytesToSize(Number(tr.cells[5].innerText));
\echo   if(tr.cells[5].innerText > 2000000000) tr.cells[5].classList.add("lime");
\echo }
\echo trs=document.getElementById("tableConten").rows;
\echo if (trs.length > 1){ 
\echo   maxevnt=Number(trs[1].cells[1].innerText);
\echo   for (let tr of trs) {
\echo   evnts=tr.cells[1];
\echo   if (evnts.innerText*1500/maxevnt > 1) evnts.innerHTML += ''''<div style="display:inline-block;width:'+ Number(evnts.innerText)*1500/maxevnt + 'px; border: 7px outset brown; border-width:7px 0; margin:0 5px;box-shadow: 2px 2px grey;">''''
\echo   }
\echo }else {
\echo   document.getElementById("tableConten").remove();
\echo   document.getElementById("time").innerText="Database wait events are not found"  
\echo }
\echo function checksess(){
\echo trs=document.getElementById("tblsess").rows;
\echo for (let tr of trs){
\echo  pid=tr.cells[0];
\echo  xidage=tr.cells[5];
\echo  stime=tr.cells[7];
\echo  if(xidage.innerText > 20) xidage.classList.add("warn");
\echo  if (blokers.indexOf(Number(pid.innerText)) > -1){ pid.classList.add("high"); pid.title="Blocker"; };
\echo  if (blkvictims.indexOf(Number(pid.innerText)) > -1) { pid.classList.add("warn"); pid.title="Victim of blocker : " + obj.victims.find(el => el.f1 == pid.innerText).f2.toString(); };
\echo  if(DurationtoSeconds(stime.innerText) > 300) stime.classList.add("warn");
\echo  if (tr.cells[2].innerText.length > 100 ){ tr.cells[2].title = tr.cells[2].innerText; 
\echo   tr.cells[2].innerText = tr.cells[2].innerText.substring(0, 100); 
\echo }
\echo }}
\echo if(document.getElementById("tblblk").rows.length < 2){ 
\echo   document.getElementById("tblblk").remove();
\echo   document.getElementById("blocking").innerText="No Blocking Sessions Found";
\echo }
\echo if(document.getElementById("tblstmnt").rows.length < 2){ 
\echo   document.getElementById("tblstmnt").remove();
\echo   document.getElementById("statements").innerText="pg_stat_statements info is not available"
\echo }
\echo trs=document.getElementById("tblchkpnt").rows;
\echo if (trs.length > 1){
\echo   tr=trs[1]
\echo   if (tr.cells[0].innerText > 10){
\echo     tr.cells[0].classList.add("high"); tr.cells[0].title="More than 10% of forced checkpoints is not desirable, increase max_wal_size";
\echo   }
\echo   if(tr.cells[1].innerText < 10 ){
\echo     tr.cells[1].classList.add("high"); tr.cells[1].title="checkpoints are too frequent. consider checkpoint_timeout=1800";
\echo   }
\echo   if(tr.cells[13].innerText > 25){
\echo     tr.cells[13].classList.add("high"); tr.cells[13].title="too many dirty pages cleaned by backends";
\echo     if(tr.cells[12].innerText < 30){
\echo       tr.cells[12].classList.add("high"); tr.cells[12].title="bgwriter is not efficient";
\echo       if(tr.cells[14].innerText < 30){
\echo         tr.cells[14].classList.add("high"); tr.cells[14].title="bgwriter could run more frequently. reduce bgwriter_delay";
\echo       }
\echo       if(tr.cells[15].innerText > 30){
\echo         tr.cells[15].classList.add("high"); tr.cells[15].title="bgwriter halts too frequently. increase bgwriter_lru_maxpages";
\echo       }
\echo     }
\echo   }
\echo }
\echo tab=document.getElementById("tblreplstat")
\echo if (tab.rows.length > 1){
\echo   for(var i=1;i<tab.rows.length;i++){
\echo     row=tab.rows[i];
\echo     [4,5,6,7,16,17].forEach(function(num){ cell=row.cells[num]; cell.title=bytesToSize(Number(cell.innerText),1024); 
\echo      if(cell.innerText > 104857600){
\echo       cell.classList.add("warn");
\echo      }else{
\echo       cell.classList.add("lime");
\echo      }
\echo     });
\echo     [14,15].forEach(function(num){  if(row.cells[num].innerText > 20) row.cells[num].classList.add("warn"); });
\echo   }
\echo }else{
\echo   tab.remove()
\echo   h2=document.getElementById("replstat")
\echo   h2.innerText="No Replication found"
\echo }
\echo document.onkeyup = function(e) {
\echo   if (e.altKey && e.which === 73) document.getElementById("topics").scrollIntoView({behavior: "smooth"});
\echo }
\echo </script>
\echo </html>
