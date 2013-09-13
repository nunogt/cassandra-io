#!/bin/bash
#
# Datastax recommends the following import procedure:
# 1. Shut down the node.
# 2. Clear all files in /var/lib/cassandra/commitlog.
# 3. Delete all *.db files in <data_directory_location>/<keyspace_name>/<column_family_name> directory, but DO NOT delete the /snapshots and /backups subdirectories.
# 4. Locate the most recent snapshot folder in <data_directory_location>/<keyspace_name>/<column_family_name>/snapshots/<snapshot_name>, and copy its contents into the <data_directory_location>/<keyspace_name>/<column_family_name> directory.
# 5. If using incremental backups, copy all contents of <data_directory_location>/<keyspace_name>/<column_family_name>/backups into <data_directory_location>/<keyspace_name>/<column_family_name>.
# 6. Restart the node.

CASSANDRA_CONF="$1"

check_exit_status() {
    if [ "$1" != "0" ] ; then
        echo "Process exited with error code: $1"
        exit $1
    fi
}

resolve_links_unix() {
    PRG="$0"
    while [ -h "$PRG" ]; do
        ls=`ls -ld "$PRG"`
        link=`expr "$ls" : '.*-> \(.*\)$'`
        if expr "$link" : '/.*' > /dev/null; then
            PRG="$link"
        else
            PRG=`dirname "$PRG"`/"$link"
        fi
    done
    CASSANDRA_IO_HOME=`dirname "$PRG"`
}

resolve_links_linux() {
    PRG="`readlink -f $0`"
    CASSANDRA_IO_HOME=`dirname "$PRG"`
}

resolve_links(){
    # GNU coreutils make this easy, so let's test for that
    case "`uname`" in
        Linux*) resolve_links_linux;;
        *) resolve_links_unix;;
    esac
}

cassandra_parse_config(){
    # we don't really parse the conf file; it's painful to do it in bash
    # let's just extract what we need for now and deal with yaml in future versions
    CASSANDRA_DATA="`cat $1 | grep data_file_directories: -A 1 | grep - | awk {'print $2'}`"
    CASSANDRA_COMMITLOG="`cat $1 | grep commitlog_directory: | awk {'print $2'}`"
    CASSANDRA_CACHES="`cat $1 | grep saved_caches_directory: | awk {'print $2'}`"
}

cassandra_info(){
    pids="`pgrep java`"
    if [ ! -z "$pids" ] ; then
        for pid in $pids ; do
            proc="`ps uwx | grep $pid | grep CassandraDaemon | grep -v grep | awk '{print $2}'`"
            if [ "$proc" == "$pid" ] ; then
                CASSANDRA_PID="$pid"
                echo "Cassandra seems to be running with pid $CASSANDRA_PID (this is my best guess)"
            fi
        done
        if [ -z "$CASSANDRA_PID" ] ; then
            echo "Couldn't reliably determine Cassandra pidfile. Is it running?"
            exit 1
        fi
    else
        echo "Cassandra is not running"
        exit 1
    fi
    if [ -z "$CASSANDRA_CONF" ] ; then
        # attemp to determine cassandra.yaml location (lots of guesswork required)
        if [ ! -f "$CASSANDRA_HOME/conf/cassandra.yaml" ] ; then
            proccwd=`lsof -p $CASSANDRA_PID | grep cwd | awk '{print $9}'`
            if [ -f "$proccwd/../conf/cassandra.yaml" ] ; then
                CASSANDRA_HOME="`dirname $proccwd`"
            fi
        fi
        CASSANDRA_CONF="$CASSANDRA_HOME/conf/cassandra.yaml"
    fi
    if [ -f "$CASSANDRA_CONF" ] ; then
        cassandra_parse_config $CASSANDRA_CONF
    else
        echo "Couldn't find cassandra.yaml configuration file."
        echo "Please specify its location by running $0 /path/to/cassandra/conf/cassandra.yaml"
        exit 1
    fi
}

cassandra_shutdown(){
    cassandra_info
    until ! kill $CASSANDRA_PID 2> /dev/null ; do
        echo "Shutting down cassandra..."
        sleep 3
    done;
}

cassandra_shutdown