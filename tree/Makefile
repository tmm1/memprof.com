default: reftree

reftree: tree.o reftree.o
	g++ -o reftree reftree.o tree.o -L. -lmongoclient -lboost_system-mt -lboost_thread-mt -lboost_filesystem-mt -lboost_program_options-mt

tree.o: tree.cpp
	g++ -Wall -O3 -ggdb -c tree.cpp

reftree.o: reftree.cpp
	g++ -Wall -O3 -ggdb -c reftree.cpp

clean:
	rm *.o
