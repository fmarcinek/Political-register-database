import psycopg2
import sys
import json

# TODO: remove cleaning mode

def cast(value):
    try:
        return int(value)
    except:
        return value

def prepareData(data):
    data = [[cast(val) for val in d[0][1:-1].split(',')] for d in data]
    return data

def writeOK(data=None):
    if data == None:
        print(json.dumps({'status': 'OK'}))
    else:
        print(json.dumps({'status': 'OK', 'data': prepareData(data)}))

def writeERROR(errorMessage):
    print(json.dumps({'status': 'ERROR', 'debug': str(errorMessage).replace('\n','')}))

def createTablesAndNewUserInDatabase(cur,dbname):
    with open('political_register.sql','r') as f:
        cur.execute(f.read())
    cur.execute("GRANT CONNECT ON DATABASE {0} TO app;".format(dbname))

def openCommand():
    openArgs = json.loads(input())['open']
    database, login, password = [openArgs[key] for key in ['database','login','password']]
    try:
        conn = psycopg2.connect('dbname={0} user={1} password={2}'.format(database,login,password))
        cur = conn.cursor()
        writeOK()
        return conn, cur, database
    except:
        writeERROR(sys.exc_info()[1])
        raise Exception

def leaderCommand(args, cur):
    leaderArgs = json.loads(args)['leader']
    timestamp, member, password = [leaderArgs[key] for key in ['timestamp','member','password']]
    try:
        cur.execute("SELECT leader_func({0},{1},'{2}');".format(timestamp, member, password))
        writeOK()
    except:
        writeERROR(sys.exc_info()[1])

def actionCommand(mode, args, cur):
    timestamp, member, password, action, project = \
        [args[key] for key in ['timestamp','member','password','action','project']]
    func_args = "_func({0},{1},'{2}',{3},{4}".format(
                timestamp,member,password,action,project)
    func_args = func_args + ",'" + mode + "'"

    if 'authority' in args:
        func_args = func_args + ',' + str(args['authority'])
    func_args = func_args + ');'

    try:
        cur.execute("SELECT support_protest" + func_args)
        writeOK()
    except:
        writeERROR(sys.exc_info()[1])

def voteCommand(mode, args, cur):
    timestamp, member, password, action = \
        [args[key] for key in ['timestamp','member','password','action']]
    func_args = "_func({0},{1},'{2}',{3}".format(
        timestamp,member,password,action)

    if mode == 'up':
        func_args = func_args + ",'u'"
    else:
        func_args = func_args + ",'d'"
    func_args = func_args + ");"

    try:
        cur.execute("SELECT upvote_downvote" + func_args)
        writeOK()
    except:
        writeERROR(sys.exc_info()[1])


def actionsCommand(args, cur):
    args = args['actions']
    timestamp, member, password = \
        [args[key] for key in ['timestamp','member','password']]
    func_args = "_func({0},{1},'{2}'".format(
             timestamp,member,password)

    if 'type' in args:
        func_args = func_args + ",'" + args['type'] + "'"
    else:
        func_args = func_args + ',NULL'

    if 'project' in args:
        func_args = func_args + ',' + str(args['project'])
    else:
        func_args = func_args + ',NULL'

    if 'authority' in args:
        func_args = func_args + ',' + str(args['authority'])
    func_args = func_args + ');'

    try:
        cur.execute("SELECT actions" + func_args)
        writeOK(cur.fetchall())
    except:
        writeERROR(sys.exc_info()[1])

def projectsCommand(args, cur):
    args = args['projects']
    timestamp, member, password = \
        [args[key] for key in ['timestamp','member','password']]
    func_args = "_func({0},{1},'{2}'".format(
            timestamp,member,password)

    if 'authority' in args:
        func_args = func_args + ',' + str(args['authority'])
    func_args = func_args + ');'

    try:
        cur.execute("SELECT projects" + func_args)
        writeOK(cur.fetchall())
    except:
        writeERROR(sys.exc_info()[1])

def votesCommand(args, cur):
    args = args['votes']
    timestamp, member, password = \
        [args[key] for key in ['timestamp','member','password']]
    func_args = "_func({0},{1},'{2}'".format(
            timestamp,member,password)

    if 'action' in args:
        func_args = func_args + ',' + str(args['action'])
    else:
        func_args = func_args + ',NULL'

    if 'project' in args:
        func_args = func_args + ',' + str(args['project'])
    func_args = func_args + ');'

    try:
        cur.execute("SELECT votes" + func_args)
        writeOK(cur.fetchall())
    except:
        writeERROR(sys.exc_info()[1])

def trollsCommand(args,cur):
    timestamp = args['trolls']['timestamp']
    try:
        cur.execute("SELECT trolls_func({0});".format(timestamp))
        data = cur.fetchall()
        writeOK(data)
    except:
        writeERROR(sys.exc_info()[1])

commandDict = {
 'support'  :   lambda json,cur: actionCommand('support', json['support'], cur), 
 'protest'  :   lambda json,cur: actionCommand('protest', json['protest'], cur),
 'upvote'   :   lambda json,cur: voteCommand('up', json['upvote'], cur),
 'downvote' :   lambda json,cur: voteCommand('down', json['downvote'], cur),
 'actions'  :   actionsCommand,
 'projects' :   projectsCommand,
 'votes'    :   votesCommand,
 'trolls'   :   trollsCommand
}

def cleanDatabase():
    openArgs = json.loads(input())['open']
    database, login, password = [openArgs[key] for key in ['database','login','password']]
    conn = psycopg2.connect("dbname={0} user={1} password='{2}'".format(database,login,password))
    cur = conn.cursor()
    writeOK()
    with open('remove.sql','r') as f:
        cur.execute(f.read())
    conn.commit()
    cur.close()
    conn.close()

if __name__=='__main__':
    conn = None
    cur = None
    try:
        if len(sys.argv) > 1 and sys.argv[1] == '--init':
            conn, cur, dbname = openCommand()
            createTablesAndNewUserInDatabase(cur,dbname)
            conn.commit()
            for line in sys.stdin:
                leaderCommand(line, cur)
                conn.commit()
        elif len(sys.argv) > 1 and sys.argv[1] == '--clean':
            cleanDatabase()
        else:
            conn, cur, dbname = openCommand()
            for line in sys.stdin:
                line = json.loads(line)
                commFunc = commandDict[list(line.keys())[0]]
                commFunc(line, cur)
                conn.commit()
    except Exception:
        print('Exception:',sys.exc_info()[1])
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()