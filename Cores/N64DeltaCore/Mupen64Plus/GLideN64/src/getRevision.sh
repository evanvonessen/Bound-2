SCRIPT_DIRECTORY=`dirname "$0"`
# Source snapshots use the pinned revision header; never rewrite it from the app repository.
if [ ! -e "$SCRIPT_DIRECTORY/../.git" ]; then exit 0; fi
rev=\"`git rev-parse --short HEAD`\"
echo current revision $rev
echo "#define PLUGIN_REVISION $rev" > $SCRIPT_DIRECTORY/Revision.h
echo "#define PLUGIN_REVISION_W L$rev" >> $SCRIPT_DIRECTORY/Revision.h
