#if !defined(__TREE_H_)
#define __TREE_H_

typedef void (*node_callback)(std::string);
typedef void (*node_callback_with_data)(std::string, void*);
typedef void (*each_node_cb)(node_callback);
typedef void (*each_result_cb)(std::vector<std::string>);
typedef void (*each_child_cb)(std::string, node_callback_with_data, void*);

void each_strongly_connected_component(each_node_cb, each_child_cb, each_result_cb);

#endif
