#!/bin/bash
#
# By default snapshots are stored under the path this script is being run from.
# If you'd rather use an asbolute path, uncomment and edit the variable below.
# 
#CASSANDRA_IO_HOME="$HOME/.cassandra-io"

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
    # GNU coreutils makes this easy, so let's test for that
    case "`uname`" in
        Linux*) resolve_links_linux;;
        *) resolve_links_unix;;
    esac 
}

bootstrap(){
    if [ -z "$CASSANDRA_IO_HOME"] ; then
        resolve_links
    fi
    mkdir -p $CASSANDRA_IO_HOME/{log,snapshots}
    check_exit_status $?
    TIMESTAMP="`date +%s`"
    NODETOOL_LOG="$CASSANDRA_IO_HOME/log/snapshot-$TIMESTAMP.log"
}

cassandra_parse_config(){
    echo "parse config"
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
    # attemp to determine cassandra.yaml path (lots of guesswork required)
    if [ ! -f "$CASSANDRA_HOME/conf/cassandra.yaml" ] ; then
        proccwd=`lsof -p $CASSANDRA_PID | grep cwd | awk '{print $9}'`
        if [ -f "$proccwd/../conf/cassandra.yaml" ] ; then
            CASSANDRA_HOME="`dirname $proccwd`"
        fi
    fi  
    CASSANDRA_CONF="$CASSANDRA_HOME/conf/cassandra.yaml"
    if [ -f "$CASSANDRA_CONF" ] ; then
        cassandra_parse_config $CASSANDRA_CONF
    else
        echo "Couldn't find cassandra.yaml configuration file."
        echo "Please specify its location by running $0 /path/to/cassandra.yaml"
        exit 1
    fi
}

locate_nodetool() {
    cassandra_info
    # can we just use nodetool, ie, is it in $PATH ?
    if [ -f "`which nodetool`" ] ; then
        NODETOOL="`which nodetool`" # yes, let's just use that
    else
        NODETOOL="$CASSANDRA_HOME/bin/nodetool" # maybe we're lucky
    fi
    # at this stage NODETOOL must be set; if it isn't, i couldn't find it
    if [ -z "$NODETOOL" ] ; then
        echo "Cassandra nodetool couldn't be located. Please include it in your PATH or set CASSANDRA_HOME"
        exit 3
    fi
}

snapshot_nodetool(){
    echo "Taking snapshot of cassandra current state"
    $NODETOOL snapshot &> $NODETOOL_LOG
    check_exit_status $?
}

snapshot_store(){
    while read line ; do
        if [[ "$line" == *directory* ]] ; then
            SNAPSHOT_NUMBER="`echo $line | awk {'print $3'}`"
        fi
    done < $NODETOOL_LOG
    SNAPSHOTS=$(find $CASSANDRA_HOME/ -type d -iname "$SNAPSHOT_NUMBER")
    if [ ! -z "$SNAPSHOTS" ] ; then
        for s in $SNAPSHOTS ; do
            rsync -aR $CASSANDRA_HOME/.`echo ${s#$CASSANDRA_HOME}` $CASSANDRA_IO_HOME/snapshots/$SNAPSHOT_NUMBER/
            check_exit_status $?
        done
    else
        echo "Couldn't determine snapshot number. I'm confused. Abort."
        exit 2
    fi
    echo "Cassandra snapshot stored at $CASSANDRA_IO_HOME/snapshots/$SNAPSHOT_NUMBER/"
    exit 0
}



bootstrap
locate_nodetool
snapshot_nodetool
snapshot_store
