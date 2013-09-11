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
    # GNU coreutils make this easy, so let's test for that
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


cassandra_info(){
    pids="`pgrep java`"
    for pid in $pids ; do
        cwd=`lsof -p $pid | grep cwd | awk '{print $9}'`
        if [ -f "$cwd/cassandra" ] ; then
            CASSANDRA_HOME="`dirname $cwd`"
            CASSANDRA_PID="$pid"
        fi
    done
    if [ ! -z "$CASSANDRA_PID" ] ; then
        echo "Cassandra seems to be running with pid $CASSANDRA_PID (this is my best guess)"
    else
        echo "Cassandra doesn't seem to be running"
        exit 1
    fi
}

locate_nodetool() {
    # guess where cassandra is running from
    if [ ! -f "$CASSANDRA_HOME" ] ; then
        cassandra_info
        echo "For higher confidence results, please set CASSANDRA_HOME environment variable"
    fi
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
