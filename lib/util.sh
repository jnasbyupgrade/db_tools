ME=`basename $0`

debug() {
  local level=$1
  shift
  if [ $level -le $DEBUG ] ; then
    local oldIFS
    oldIFS=$IFS
    unset IFS
    # Output debug level if it's over threashold
    if [ $DEBUG -ge ${DEBUGEXTRA:-10} ]; then
      echo "${level}: $@" 1>&2
    else
      echo "$@" 1>&2
    fi
    IFS=$oldIFS
  fi
}

debug_vars () {
  level=$1
  shift
  local out=''
  local value=''
  for variable in $*; do
    eval value=\$$variable
    out="$out $variable='$value'"
  done
  debug $level $out
}


error() {
  while [ "$1" = "-c" -o "$1" = "-n" ]; do
    if [ "$1" = "-n" ]; then
      lineno=$2
      shift 2
    fi
    if [ "$1" = "-c" ]; then
      local stack=0
      shift
    fi
  done

  echo "$@" 1>&2
  if [ -n "$stack" ]; then
    stacktrace 1 # Skip our own frame
  else
    [ -n "$lineno" ] && echo "File \"$0\", line $lineno" 1>&2
  fi
}

die() {
  return=$1
  debug_vars 99 return
  shift
  error "$@"
  [ $DEBUG -gt 0 ] && stacktrace 1
  if [ -n "$DIE_EXTRA" ]; then
    local lineno=''
    error
    error $DIE_EXTRA
  fi
  exit $return
}

file_sanity() {
  for file in "$@"; do
    [ -e "$file" ] || die 1 "error: file '$file' does not exist"
    [ -r "$file" ] || die 1 "error: file '$file' is not readable"
  done
}

#
# run_psql debug_level <psql arguments>
#
# debug_level is passed to debugging commands
#
# Must pass at least 1 psql argument
run_psql() {
  local debug_level cmd
  [ $# -ge 2 ] || die invalid invocation of run_psql

  debug_level=$1
  shift

  cmd='psql --no-psqlrc'
  debug $debug_level $cmd "$@"
  $cmd "$@"
}

db_exists() {
    local exists
    exists=$(run_psql 29 -qtc "SELECT EXISTS( SELECT 1 FROM pg_database WHERE datname = '$dbname' )" postgres $@ | tr -d ' ')
    if [ "$exists" == "t" ]; then
        return 0
    else
        return 1
    fi
}

set_PGCONFIG() {
  debug 99 set_PGCONFIG
  debug_vars 99 PGCONFIG
  if [[ -z ${PGCONFIG+x} ]]; then
    PGCONFIG=$(which pg_config)
    debug_vars 199 PGCONFIG
  fi
  debug_vars 98 PGCONFIG
  [[ -n "$PGCONFIG" ]] || die 1 'Unable to find pg_config; add it to $PATH or set $PGCONFIG'
}

set_PGXN() {
  debug 99 set_PGXN
  debug_vars 99 PGXN
  if [[ -z ${PGXN+x} ]]; then
    PGXN=$(which pgxn)
  fi
  [[ -n "$PGXN" ]] || die 1 "Unable to find pgxn; add it to \$PATH or set \$PGXN

PGXN install instructions are at https://pgxn.github.io/pgxnclient/"
}

# This is a separate function to allow for customization. All that ultimately matters is that EXTDIR gets set.
pgxn_install_setup() {
  debug 99 pgxn_install_setup
  debug_vars 99 EXTDIR
  if [[ -z ${EXTDIR+x} ]]; then
    set_PGCONFIG

    EXTDIR=$($PGCONFIG --sharedir)/extension || die 1 "$PGCONFIG returned $?"
  fi
  debug_vars 88 EXTDIR
}

pgxn_install() {
    local name
    local version
    local options
    local namever
    name=$1
    shift
    if echo $1 | egrep -q '^-'; then
        options=$@
    else
        version=$1
        shift
        options=$@
    fi

    if [ -n "$version" ]; then
        # It's tempting to allow >= and what-not, but that will break version checking (see below)
        namever="$name=$version"
    else
        namever=$name
    fi
    debug_vars 7 name version namever options

    #PGXN=${PGXN:-}
    #EXTDIR=${EXTDIR:-}
    set_PGXN
    pgxn_install_setup
    [[ -n "$EXTDIR" ]] || die 9 '$EXTDIR must be set. See pgxn_install_set_EXTDIR()'

    # Bounce out if already installed and same version
    local control
    control=$EXTDIR/${name}.control
    if [ -f $control ]; then
        # If we don't care about version bounce out now
        [ -z "$version" ] && return

        instver=$(grep default_version $control | cut -d"'" -f2)
        debug_vars 9 instver
        [ -n "$instver" ] || die 4 $'\nunable to determine installed version of $name'

        # Return if it matches
        [ "$instver" = "$version" ] && return
    fi

    echo -n "Installing $namever from pgxn"
    [ -n "$options" ] && echo -n " with options '$options'"
    echo

    debug 9 $PGXN install --sudo sudo $namever $options
    $PGXN install --sudo sudo $namever $options || die 3 $'\npgxn returned' $?
    echo done
    echo
}


stacktrace () {
  debug 200 "stacktrace( $@ )"
  local frame=${1:-0}
  local line=''
  local file=''
  debug_vars 200 frame line file

  # NOTE the stderr redirect below!
  (
    echo
    echo Stacktrace:
    while caller $frame; do
      frame=$(( $frame + 1 ))
    done | while read line function file; do
      if [ -z "$function" -o "$function" = main ]; then
        echo "$file: line $line"
      else
        echo "$file: line $line: function $function"
      fi
    done
  ) 1>&2
}

debug_sanity() {
  # Ensure that DEBUG is set
  if [ ${DEBUG:-0} = 0 ] ; then
    [ -n "$1" ] && error "WARNING: \$DEBUG not set"
    DEBUG=0
  fi
}
debug_sanity



# vi: expandtab ts=2 sw=2
