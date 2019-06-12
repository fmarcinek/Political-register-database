DROP TRIGGER global_id_uniqueness_members_trigger ON members;
DROP TRIGGER global_id_uniqueness_actions_trigger ON actions;
DROP TRIGGER global_id_uniqueness_projects_trigger ON projects;

DROP TABLE members CASCADE;
DROP TABLE votes CASCADE;
DROP TABLE projects CASCADE;
DROP TABLE actions CASCADE;
DROP TABLE global_ids CASCADE;

DROP FUNCTION leader_func(bigint,integer,text);
DROP FUNCTION global_id_uniqueness_func();
DROP FUNCTION global_id_uniqueness_projects_func();
DROP FUNCTION save_member_func(integer,text,timestamp);
DROP FUNCTION member_authorization_func(integer,text,bigint);
DROP FUNCTION check_leader_rank_func(integer);
DROP FUNCTION check_if_member_is_active_func(integer,timestamp);

DROP FUNCTION support_protest_func(bigint,integer,text,integer,integer,action_types,integer);
DROP FUNCTION upvote_downvote_func(bigint,integer,text,integer,vote_types);
DROP FUNCTION auxiliary_actions_func();
DROP FUNCTION actions_func(bigint,integer,text,action_types,integer,integer);
DROP FUNCTION projects_func(bigint,integer,text,integer);
DROP FUNCTION votes_func(bigint,integer,text,integer,integer);
DROP FUNCTION trolls_func(bigint);

DROP DOMAIN action_types;
DROP DOMAIN vote_types;

REVOKE ALL PRIVILEGES ON DATABASE student FROM app;
DROP USER app;