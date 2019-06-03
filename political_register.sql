CREATE DOMAIN action_types AS char(7)
CHECK (VALUE IN ('support','protest'));

CREATE DOMAIN vote_types AS char(1)
CHECK (VALUE IN ('u','d')) NOT NULL;

CREATE TABLE members (
    id              integer PRIMARY KEY,
    password        text NOT NULL,
    last_post_date  timestamp NOT NULL,
    is_leader       boolean DEFAULT false,
    upvotes         integer DEFAULT 0,
    downvotes       integer DEFAULT 0
);

CREATE TABLE projects (
    id              integer PRIMARY KEY,
    authority_id    integer NOT NULL
);

CREATE TABLE actions (
    id          integer PRIMARY KEY,
    member_id   integer NOT NULL,
    project_id  integer NOT NULL,
    action_type action_types NOT NULL,
    FOREIGN KEY (member_id) REFERENCES members (id),
    FOREIGN KEY (project_id) REFERENCES projects (id)
);

CREATE TABLE votes (
    member_id   integer NOT NULL,
    action_id   integer NOT NULL,
    vote_type   vote_types NOT NULL,
    PRIMARY KEY (member_id, action_id),
    FOREIGN KEY (member_id) REFERENCES members (id),
    FOREIGN KEY (action_id) REFERENCES actions (id)
);

CREATE TABLE global_ids (
    id      integer PRIMARY KEY
);

-- CREATE OR REPLACE FUNCTION check_and_deactivate_func() RETURNS TRIGGER
--     AS $$
--     BEGIN
--         UPDATE members SET is_active = false
--         WHERE last_post_date IS NOT NULL 
--             AND NEW.last_post_date - last_post_date > interval '1 year';

--         IF (TG_OP = 'UPDATE' AND NEW.last_post_date - OLD.last_post_date > interval '1 year') THEN
--             RETURN OLD;
--         ELSE
--             RETURN NEW;
--         END IF;
--     END;
--     $$ LANGUAGE plpgsql;

-- CREATE TRIGGER members_deactivation_trigger BEFORE INSERT OR UPDATE OF last_post_date
--     ON members FOR EACH ROW EXECUTE PROCEDURE check_and_deactivate_func();

CREATE OR REPLACE FUNCTION leader_func(action_time bigint,
                                       member integer,
                                       passwd text) 
                                       RETURNS VOID
    AS $$
    DECLARE
        date_in_timestamp_format timestamp;
    BEGIN
        date_in_timestamp_format = TO_TIMESTAMP(action_time) AT TIME ZONE 'UTC';
        INSERT INTO members (id,password,last_post_date,is_leader) 
        VALUES (member, crypt(passwd, gen_salt('md5')), date_in_timestamp_format, true);
    END; 
    $$ LANGUAGE plpgsql
    SECURITY INVOKER;

CREATE OR REPLACE FUNCTION save_member_func(member integer,
                                            passwd text,
                                            action_time timestamp)
                                            RETURNS VOID
    AS $$
    BEGIN
        INSERT INTO members (id,password,last_post_date)
        VALUES (member, crypt(passwd, gen_salt('md5')),action_time);
    END;
    $$ LANGUAGE plpgsql
    SECURITY DEFINER;

CREATE OR REPLACE FUNCTION member_authorization_func(member integer,
                                                     passwd text,
                                                     action_time bigint)
                                                     RETURNS VOID
    AS $$
    DECLARE
        pswhash text;
        date_in_timestamp_format timestamp;
    BEGIN
        date_in_timestamp_format = TO_TIMESTAMP(action_time) AT TIME ZONE 'UTC';
        SELECT password INTO pswhash FROM members WHERE id = member;
        IF NOT FOUND THEN
            PERFORM save_member_func(member, passwd, date_in_timestamp_format);
        ELSE
            IF (pswhash = crypt(passwd, pswhash)) THEN
                PERFORM check_if_member_is_active_func(member, date_in_timestamp_format);
            ELSE
                RAISE EXCEPTION 'Authorization error on member id: %', member
                USING HINT = 'Please enter correct password.';
            END IF;
        END IF;
    END;
    $$ LANGUAGE plpgsql
    SECURITY DEFINER;

CREATE OR REPLACE FUNCTION check_if_member_is_active_func(member integer, date timestamp) RETURNS VOID
    AS $$
    DECLARE
        active boolean;
        last_activity timestamp;
    BEGIN
        SELECT last_post_date INTO last_activity FROM members WHERE id = member;
        IF (date - last_activity <= interval '1 year') THEN
            UPDATE members SET last_post_date = date WHERE id = member;
        ELSE
            RAISE EXCEPTION 'Authorization error: Member with id % is deactivated
                                         due to one year inactivity.', member;
        END IF;
    END;
    $$ LANGUAGE plpgsql
    SECURITY DEFINER;

CREATE OR REPLACE FUNCTION check_leader_rank_func(member integer) RETURNS VOID
    AS $$
    DECLARE
        has_access boolean;
    BEGIN
        SELECT is_leader INTO has_access FROM members WHERE id = member;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Authorization error: There is no leader with id: %', member;
        ELSE
            IF NOT has_access THEN
                RAISE EXCEPTION 'Authorization error: Member with id % has not leader rights.', member;
            END IF;
        END IF;
    END;
    $$ LANGUAGE plpgsql
    SECURITY DEFINER;

CREATE OR REPLACE FUNCTION support_protest_func(action_time bigint,
                                                member integer,
                                                passwd text, 
                                                action integer,
                                                project integer,
                                                action_type action_types,
                                                authority integer DEFAULT NULL)
                                                RETURNS VOID
    AS $$
    DECLARE
        auth_id integer;
    BEGIN
        PERFORM member_authorization_func(member,passwd,action_time);
        SELECT authority_id FROM projects INTO auth_id WHERE id = project;
        IF NOT FOUND THEN
            IF (authority IS NULL) THEN
                RAISE EXCEPTION 'Authority attribute error: project % has not associated authority id.', project;
            ELSE
                INSERT INTO projects VALUES (project, authority);
            END IF;
        END IF;

        INSERT INTO actions VALUES (action,member,project,action_type);
    END;
    $$ LANGUAGE plpgsql
    SECURITY DEFINER;

CREATE OR REPLACE FUNCTION upvote_downvote_func(action_time bigint,
                                                member integer,
                                                passwd text,
                                                action integer,
                                                vote_type vote_types)
                                                RETURNS VOID
    AS $$
    DECLARE
        certain_id integer;
        author_id integer;
    BEGIN
        PERFORM member_authorization_func(member,passwd,action_time);
        SELECT member_id INTO certain_id FROM votes WHERE member_id = member
                                                          AND action_id = action;
        IF NOT FOUND THEN
            SELECT id INTO certain_id FROM actions WHERE id = action;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Action with id % does not exist. Cannot vote on it.', action;
            END IF;
        ELSE
            RAISE EXCEPTION 'Member with id % has just voted on action %.', member, action;
        END IF;

        SELECT member_id INTO author_id FROM actions WHERE id = action;
    
        INSERT INTO votes VALUES (member, action, vote_type);

        IF (vote_type = 'u') THEN
            UPDATE members SET upvotes = upvotes + 1 WHERE members.id = author_id;
        ELSE
            UPDATE members SET downvotes = downvotes + 1 WHERE members.id = author_id;
        END IF;
    END;
    $$ LANGUAGE plpgsql
    SECURITY DEFINER;

CREATE OR REPLACE FUNCTION auxiliary_actions_func() RETURNS TABLE (action integer,
                                                                   type action_types,
                                                                   project integer,
                                                                   authority integer,
                                                                   upvotes bigint,
                                                                   downvotes bigint)
    AS $$
    BEGIN
        RETURN QUERY(
            SELECT subq.id,
                   subq.action_type,
                   subq.project_id,
                   p.authority_id,
                   subq.c1,
                   subq.c2
            FROM (SELECT a.id,
                         a.action_type,
                         a.project_id,
                         COUNT(vote_type) FILTER (WHERE vote_type = 'u') AS c1,
                         COUNT(vote_type) FILTER (WHERE vote_type = 'd') AS c2
                  FROM actions a
                  LEFT JOIN votes v ON v.action_id = a.id
                  GROUP BY a.id) subq
            JOIN projects p ON subq.project_id = p.id);
    END;
    $$ LANGUAGE plpgsql
    SECURITY DEFINER;

CREATE OR REPLACE FUNCTION actions_func(action_time bigint,
                                        member integer, 
                                        passwd text,
                                        action_type action_types DEFAULT NULL,
                                        project_id integer DEFAULT NULL,
                                        authority_id integer DEFAULT NULL)
                                        RETURNS TABLE (action integer,
                                                       type action_types,
                                                       project integer,
                                                       authority integer,
                                                       upvotes bigint,
                                                       downvotes bigint)
    AS $$
    BEGIN
        PERFORM check_leader_rank_func(member);
        PERFORM member_authorization_func(member,passwd,action_time);

        IF (project_id IS NOT NULL) THEN
            IF (action_type IS NULL) THEN
                RETURN QUERY(
                    SELECT * FROM auxiliary_actions_func() aux
                    WHERE aux.project = project_id
                    ORDER BY aux.action);
            ELSE
                RETURN QUERY(
                    SELECT * FROM auxiliary_actions_func() aux
                    WHERE aux.project = project_id AND aux.type = action_type
                    ORDER BY aux.action);
            END IF;
        ELSIF (authority_id IS NOT NULL) THEN
            IF (action_type IS NULL) THEN
                RETURN QUERY(
                    SELECT * FROM auxiliary_actions_func() aux
                    WHERE aux.authority = authority_id
                    ORDER BY aux.action);
            ELSE
                RETURN QUERY(
                    SELECT * FROM auxiliary_actions_func() aux
                    WHERE aux.authority = authority_id AND aux.type = action_type
                    ORDER BY aux.action);
            END IF;
        ELSE
            IF (action_type IS NULL) THEN
                RETURN QUERY(
                    SELECT * FROM auxiliary_actions_func()
                    ORDER BY member);
            ELSE
                RETURN QUERY(
                    SELECT * FROM auxiliary_actions_func() aux
                    WHERE aux.type = action_type
                    ORDER BY aux.action);
            END IF;
        END IF;
    END;
    $$ LANGUAGE plpgsql
    SECURITY DEFINER;

CREATE OR REPLACE FUNCTION projects_func(action_time bigint,
                                         member integer, 
                                         passwd text,
                                         authority_ integer DEFAULT NULL)
                                         RETURNS TABLE (project integer,
                                                        authority integer)
    AS $$
    BEGIN
        PERFORM check_leader_rank_func(member);
        PERFORM member_authorization_func(member,passwd,action_time);

        IF (authority_ IS NULL) THEN
            RETURN QUERY(
                SELECT id, authority_id
                FROM projects
                ORDER BY project ASC);
        ELSE
            RETURN QUERY(
                SELECT id, authority_id
                FROM projects
                WHERE authority_id = authority_
                ORDER BY project ASC);
        END IF;
    END;
    $$ LANGUAGE plpgsql
    SECURITY DEFINER;

CREATE OR REPLACE FUNCTION votes_func(action_time bigint,
                                      member_ integer, 
                                      passwd text,
                                      action integer DEFAULT NULL, 
                                      project integer DEFAULT NULL) 
                                      RETURNS TABLE (member integer,
                                                     upvotes bigint,
                                                     downvotes bigint)
    AS $$
    BEGIN
        PERFORM check_leader_rank_func(member_);
        PERFORM member_authorization_func(member_,passwd,action_time);

        IF (action IS NOT NULL) THEN
            RETURN QUERY(
                WITH selected_votes AS (
                    SELECT * FROM votes WHERE action_id = action)
                SELECT id,
                       COUNT(vote_type) FILTER (WHERE vote_type = 'u'),
                       COUNT(vote_type) FILTER (WHERE vote_type = 'd')
                FROM members LEFT JOIN selected_votes ON id = member_id
                GROUP BY id
                ORDER BY id ASC);
        ELSIF (project IS NOT NULL) THEN
            RETURN QUERY(
                WITH selected_votes AS (
                    SELECT member_id,action_id,vote_type
                    FROM votes JOIN actions ON id = action_id
                    WHERE project_id = project)
                SELECT id,
                       COUNT(vote_type) FILTER (WHERE vote_type = 'u'),
                       COUNT(vote_type) FILTER (WHERE vote_type = 'd')
                FROM members LEFT JOIN selected_votes ON id = member_id
                GROUP BY id
                ORDER BY id ASC);
        ELSE
            RETURN QUERY(
                SELECT id,
                       COUNT(vote_type) FILTER (WHERE vote_type = 'u'),
                       COUNT(vote_type) FILTER (WHERE vote_type = 'd')
                FROM members LEFT JOIN votes ON id = member_id
                GROUP BY id
                ORDER BY id ASC);
        END IF;
    END;
    $$ LANGUAGE plpgsql
    SECURITY DEFINER;

CREATE OR REPLACE FUNCTION trolls_func(action_time bigint) RETURNS TABLE(member integer,
                                                                         upvotes integer,
                                                                         downvotes integer,
                                                                         active text)
    AS $$
    DECLARE
        actual_date timestamp;
    BEGIN
        actual_date = TO_TIMESTAMP(action_time) AT TIME ZONE 'UTC';
        RETURN QUERY(
            SELECT m.id, m.upvotes, m.downvotes, (CASE WHEN actual_date - last_post_date <= interval '1 year'
                                                 THEN 'true' ELSE 'false' END)
            FROM members m
            WHERE m.downvotes > m.upvotes
            ORDER BY 
                member ASC,
                m.downvotes - m.upvotes DESC);
    END;
    $$ LANGUAGE plpgsql
    SECURITY DEFINER;

REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA PUBLIC FROM PUBLIC;
REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA PUBLIC FROM PUBLIC;

CREATE USER app ENCRYPTED PASSWORD 'qwerty';
GRANT EXECUTE ON FUNCTION support_protest_func(bigint,integer,text,integer,integer,action_types,integer) TO app;
GRANT EXECUTE ON FUNCTION upvote_downvote_func(bigint,integer,text,integer,vote_types) TO app;
GRANT EXECUTE ON FUNCTION actions_func(bigint,integer,text,action_types,integer,integer) TO app;
GRANT EXECUTE ON FUNCTION projects_func(bigint,integer,text,integer) TO app;
GRANT EXECUTE ON FUNCTION votes_func(bigint,integer,text,integer,integer) TO app;
GRANT EXECUTE ON FUNCTION trolls_func(bigint) TO app;