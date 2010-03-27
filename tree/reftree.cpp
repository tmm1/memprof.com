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

typedef map< int, set<int> > Graph;
Graph *metaGraph = NULL;

void
calc_meta_graph() {
  BSONObj o, p, q;
  BSONObj emptyObj = BSONObj();

  if (metaGraph)
    delete metaGraph;
  metaGraph = new Graph();

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
      connection->update("memprof_datasets.stdlib_groups", BSON("_id" << id), BSON("$set" << BSON("refs" << refs_v)));

      (*metaGraph)[id] = refs;
    }
  }

  cout << endl << "  created w/ size: " << metaGraph->size();
}

map<int,int>* numMembers;

int
dfs_size_for(int node) {
  map<int,int>::iterator members_it;
  Graph::iterator graph_it;

  set<int> visited;

  vector<int> to_visit;
  to_visit.push_back(node);

  int size = 0;

  while (to_visit.size() > 0) {
    int cur = to_visit[to_visit.size()-1];
    to_visit.pop_back();

    if (visited.find(cur) == visited.end()) {
      visited.insert(cur);

      int n_members = 0;
      members_it = numMembers->find(cur);

      if (members_it == numMembers->end()) {
        auto_ptr<DBClientCursor> cursor = connection->query("memprof_datasets.stdlib_groups", BSON("_id" << cur));
        if (cursor->more()) { // should get exactly one response
          BSONObj o = cursor->next();

          BSONObjIterator i( o["members"].embeddedObject() );
          while (i.more()) {
            BSONElement e = i.next();
            n_members += 1;
          }

          (*numMembers)[cur] = n_members;
        }
      } else {
        n_members = members_it->second;
      }

      size += n_members;

      graph_it = metaGraph->find(cur);
      if (graph_it != metaGraph->end()) {
        set<int> refs = graph_it->second;
        set<int>::iterator refs_it = refs.begin();
        while (refs_it != refs.end()) {
          to_visit.push_back(*refs_it++);
        }
      }

    }
  }

  return size;
}

void
calc_sizes() {
  BSONObj emptyObj = BSONObj();
  numMembers = new map<int,int>();

  auto_ptr<DBClientCursor> cursor = connection->query("memprof_datasets.stdlib_groups", emptyObj);
  while( cursor->more() ) {
    BSONObj o = cursor->next();

    int id = o.getIntField("_id");
    int size = dfs_size_for(id);

    connection->update("memprof_datasets.stdlib_groups", BSON("_id" << id), BSON("$set" << BSON("size" << size)));
  }

  delete numMembers;
}

void
run() {
  cout << "finding strongly connected components...";
  cout.flush();

  find_sccs();

  cout << endl << "calculating meta graph...";
  cout.flush();

  calc_meta_graph();

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
