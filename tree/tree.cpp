#include <iostream>
#include <string>
#include <vector>
#include <map>

using namespace std;

#include "tree.h"

map<string, int> id_map;
vector<string> stack;
int sub_minimum_id;
each_child_cb for_each_child;
each_result_cb for_each_result;

int each_strongly_connected_component_from(string node);

void do_each_strongly_connected_from(string child, void *data)
{
  map<string, int>::size_type *minimum_id = (map<string, int>::size_type *)data;
  map<string, int>::iterator it;
  map<string, int>::size_type sub_minimum_id;

  it = id_map.find(child);

  if (it != id_map.end()) {
    int child_id = it->second;
    if (child_id != -1 && child_id < *minimum_id) {
      *minimum_id = child_id;
    }
  }
  else {
    sub_minimum_id = each_strongly_connected_component_from(child);
    if (sub_minimum_id < *minimum_id) {
      *minimum_id = sub_minimum_id;
    }
  }
}

int each_strongly_connected_component_from(string node)
{
  vector<string>::size_type stack_length = stack.size();
  map<string, int>::size_type minimum_id, node_id;

  minimum_id = node_id = id_map.size();
  id_map.insert(pair<string, int>(node, id_map.size()));
  stack.push_back(node);

  (*for_each_child)(node, do_each_strongly_connected_from, &minimum_id);

  if (node_id == minimum_id) {
    vector<string>::size_type component_size = stack.size() - stack_length;
    vector<string>::iterator it = stack.end();
    it -= component_size;

    vector<string> component;
    while (it != stack.end()) {
      component.push_back(*it++);
    }
    (*for_each_result)(component);

    int n = 0;
    for (; n < component_size; n++) { stack.pop_back(); }
  }

  return minimum_id;
}

void each_strongly_connected_component(each_node_cb, each_child_cb, each_result_cb);

void do_each_strongly_connected_component(string node)
{
  if (id_map.find(node) == id_map.end()) {
    each_strongly_connected_component_from(node);
  }
}

void each_strongly_connected_component(each_node_cb for_each_node, each_child_cb each_child, each_result_cb each_result)
{
  for_each_child = each_child;
  for_each_result = each_result;
  id_map.clear();
  stack.clear();

  for_each_node(do_each_strongly_connected_component);
  return;
}

/***********************************

static void do_each_child(string node, node_callback_with_data cb, void *data)
{
  if (node.compare("1") == 0)
    cb("2", data);
  else if (node.compare("2") == 0) {
    cb("3", data);
    cb("4", data);
  } else if (node.compare("3") == 0)
    cb("2", data);
}

static void do_each_result(vector<string> results)
{
  vector<string>::iterator it = results.begin();
  cout << "got result: ";
  while (it != results.end()) {
    cout << *it++ << " ";
  }
  cout << endl;
}

int main()
{
  for_each_child = &do_each_child;
  for_each_result = &do_each_result;

  do_each_strongly_connected_component("1");
  do_each_strongly_connected_component("2");
  do_each_strongly_connected_component("3");
  do_each_strongly_connected_component("4");
}

/***********************************/
