default: tree.o reftree.o
	g++ -o reftree -lmongoclient -lboost_thread-mt -lboost_filesystem-mt -lboost_system-mt -lboost_program_options-mt reftree.o tree.o

tree.o: tree.cpp
	g++ -O0 -ggdb -c tree.cpp

reftree.o: reftree.cpp
	g++ -O0 -ggdb -c reftree.cpp

clean:
	rm *.{o}
