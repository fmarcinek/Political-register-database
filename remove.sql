DROP TRIGGER members_deactivation_trigger ON members;

DROP TABLE members CASCADE;
DROP TABLE votes CASCADE;
DROP TABLE votes_summary CASCADE;
DROP TABLE projects CASCADE;
DROP TABLE actions CASCADE;


DROP FUNCTION leader_func(integer,text);
DROP FUNCTION check_and_deactivate_func();
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
DROP FUNCTION trolls_func();

DROP DOMAIN action_types;
DROP DOMAIN vote_types;

REVOKE ALL PRIVILEGES ON DATABASE student FROM app;
DROP USER app;