return sub {
    sleep 2;
    die "error from nested nested";
};
