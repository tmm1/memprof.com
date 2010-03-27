#include <mongo/client/dbclient.h>
#include <stdlib.h>
#include <stdio.h>
#include "tree.h"

using namespace mongo;
DBClientConnection *connection;

void do_each_node(node_callback cb) {
  BSONObj o;
  Query q = Query(BSONObj());
  BSONObj fields = BSON("_id" << 1);

  auto_ptr<DBClientCursor> cursor = connection->query("memprof_datasets.stdlib_refs", q, 0, 0, &fields, 0);
  while( cursor->more() ) {
    o = cursor->next();
    cb(o["_id"].str());
  }
}

static void do_each_child(string node, node_callback_with_data cb, void *data)
{
  BSONObj o;
  Query q = QUERY("_id" << node << "refs" << BSON("$exists" << true));

  auto_ptr<DBClientCursor> cursor = connection->query("memprof_datasets.stdlib_refs", q, 1);
  while( cursor->more() ) {
    o = cursor->next();

    BSONObjIterator i( o["refs"].embeddedObject() );
    while ( i.more() ) {
      BSONElement e = i.next();
      cb(e.str(), data);
    }

    break; // only one result
  }
}

static void do_each_component(vector<string> results) {
  static int i = 1;
  connection->insert("memprof_datasets.stdlib_groups", BSON("_id" << i++ << "members" << results));
}

void
find_sccs() {
  each_strongly_connected_component(&do_each_node, &do_each_child, &do_each_component);
  connection->ensureIndex("memprof_datasets.stdlib_groups", BSON("members" << 1));
}

void
calc_meta_tree() {
  BSONObj o, p, q;
  BSONObj emptyObj = BSONObj();

  auto_ptr<DBClientCursor> cursor = connection->query("memprof_datasets.stdlib_groups", emptyObj);
  while( cursor->more() ) {
    o = cursor->next();
    int id = o.getIntField("_id");

    set<string> list;

    auto_ptr<DBClientCursor> rcursor = connection->query("memprof_datasets.stdlib_refs", BSON("_id" << BSON("$in" << o["members"])));
    while( rcursor->more() ) {
      p = rcursor->next();

      BSONObjIterator i( p["refs"].embeddedObject() );
      while ( i.more() ) {
        BSONElement e = i.next();
        list.insert(e.str());
      }
    }

    vector<string> list_v(list.begin(), list.end());
    set<int> refs;

    auto_ptr<DBClientCursor> gcursor = connection->query("memprof_datasets.stdlib_groups", BSON("members" << BSON("$in" << list_v)));
    while( gcursor->more() ) {
      q = gcursor->next();
      int r = q.getIntField("_id");
      if (r != id)
        refs.insert(r);
    }

    if (refs.size() > 0) {
      vector<int> refs_v(refs.begin(), refs.end());
      connection->update("memprof_datasets.stdlib_groups", BSON("_id" << o["_id"]), BSON("$set" << BSON("refs" << refs_v)));
    }
  }
}

int
dfs_size_for(int node) {
  set<int> visited;

  vector<int> to_visit;
  to_visit.push_back(node);

  int size = 0;

  while (to_visit.size() > 0) {
    int cur = to_visit[to_visit.size()-1];
    to_visit.pop_back();

    if (visited.find(cur) == visited.end()) {
      visited.insert(cur);

      auto_ptr<DBClientCursor> cursor = connection->query("memprof_datasets.stdlib_groups", BSON("_id" << cur));
      if (cursor->more()) { // should get exactly one response
        BSONObj o = cursor->next();

        BSONObjIterator i( o["members"].embeddedObject() );
        while (i.more()) {
          BSONElement e = i.next();
          size += 1;
        }

        if (o.hasField("refs")) {
          BSONObjIterator ii( o["refs"].embeddedObject() );
          while (ii.more()) {
            BSONElement e = ii.next();
            to_visit.push_back(e.numberInt());
          }
        }

      }
    }
  }

  return size;
}

void
calc_sizes() {
  BSONObj emptyObj = BSONObj();

  auto_ptr<DBClientCursor> cursor = connection->query("memprof_datasets.stdlib_groups", emptyObj);
  while( cursor->more() ) {
    BSONObj o = cursor->next();

    int id = o.getIntField("_id");
    int size = dfs_size_for(id);

    connection->update("memprof_datasets.stdlib_groups", BSON("_id" << id), BSON("$set" << BSON("size" << size)));
  }
}

void
run() {
  cout << "finding strongly connected components...";
  cout.flush();

  find_sccs();

  cout << endl << "calculating meta graph...";
  cout.flush();

  calc_meta_tree();

  cout << endl << "calculating tree sizes...";
  cout.flush();

  calc_sizes();

  cout << endl << "done." << endl;
}

int
main() {
  try {
    connection = new DBClientConnection();
    connection->connect("localhost");
    cout << "connected ok." << endl;
    run();
  } catch( DBException &e ) {
    cout << "caught " << e.what() << endl;
  }
  return 0;
}
