use IO::Handle;
#STDOUT->autoflush(1);
for (0..9999){
    #sleep 1;
    print "Hi";
}

print "bye";

1;
