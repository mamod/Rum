package Rum::RBTree;
use strict;
use warnings;
use Data::Dumper;

sub new {
    my ($class,$comparator) = @_;
    my $this = {};
    $this->{_root} = undef;
    $this->{_comparator} = $comparator || \&compare;
    $this->{size} = 0;
    bless $this,$class;
}

sub is_red {
    my ($node) = @_;
    return $node && $node->{red};
}

sub compare {
    my ($a,$b) = @_;
    return 1 if $a > $b;
    return 0;
}

sub insert {
    my ($this,$data) = @_;
    my $ret = 0;
    if( !$this->{_root}) {
        #empty tree
        $this->{_root} = Rum::RBTree::Node->new($data);
        $ret = 1;
        $this->{size}++;
    } else {
        my $head = Rum::RBTree::Node->new(); #fake tree root
        
        my $dir = 0;
        my $last = 0;
        
        #setup
        my $gp = undef; # grandparent
        my $ggp = $head; # grand-grand-parent
        my $p = undef; # parent
        my $node = $this->{_root};
        $ggp->{right} = $this->{_root};

        #search down
        while(1) {
            if (!$node) {
                #insert new node at the bottom
                $node = Rum::RBTree::Node->new($data);
                $p->set_child($dir, $node);
                $ret = 1;
                $this->{size}++;
            } elsif($node->{left} && $node->{left}->{red} && $node->{right} && $node->{right}->{red}) {
                #color flip
                $node->{red} = 1;
                $node->{left}->{red} = 0;
                $node->{right}->{red} = 0;
            }
            
            #fix red violation
            if( $node && $node->{red} && $p && $p->{red} ) {
                my $dir2 = $ggp->{right} == $gp;
                my $child = $p->get_child($last);
                if($node && $child && $node eq $child) {
                    $ggp->set_child($dir2, single_rotate($gp, !$last));
                } else {
                    $ggp->set_child($dir2, double_rotate($gp, !$last));
                }
            }
            
            my $cmp = $this->{_comparator}->($node->{data}, $data);
            
            #stop if found
            last if $cmp == 0;
            
            $last = $dir;
            $dir = $cmp < 0;
            
            #update helpers
            if( defined $gp ) {
                $ggp = $gp;
            }
            $gp = $p;
            $p = $node;
            $node = $node->get_child($dir);
        }
        
        #update root
        $this->{_root} = $head->{right};
    }

    #make root black
    $this->{_root}->{red} = 0;
    return $ret;
}

#returns true if removed, false if not found
sub remove {
    my ($this,$data) = @_;
    if( !$this->{_root} ) {
        return 0;
    }

    my $head = Rum::RBTree::Node->new(); #fake tree root
    my $node = $head;
    $node->{right} = $this->{_root};
    my $p = undef; # parent
    my $gp = undef; # grand parent
    my $found = undef; # found item
    my $dir = 1;

    while( $node->get_child($dir) ) {
        my $last = $dir;

        #update helpers
        $gp = $p;
        $p = $node;
        $node = $node->get_child($dir);
        
        my $cmp = $this->{_comparator}->($data, $node->{data});
        
        $dir = $cmp > 0;
        
        #save found node
        if( $cmp == 0) {
            $found = $node;
        }
        
        #push the red node down
        if( !($node || $node->{red}) && !is_red($node->get_child($dir))) {
            my $child = $node->get_child(!$dir);
            if($child && $child->{red}) {
                my $sr = single_rotate($node, $dir);
                $p->set_child($last, $sr);
                $p = $sr;
            } elsif (!($child && $child->{red})) {
                my $sibling = $p->get_child(!$last);
                if( $sibling ) {
                    if(!is_red($sibling->get_child(!$last)) && !is_red($sibling->get_child($last))) {
                        #color flip
                        $p->{red} = 0;
                        $sibling->{red} = 1;
                        $node->{red} = 1;
                    } else {
                        my $dir2 = $gp->{right} == $p;
                        
                        if(is_red($sibling->get_child($last))) {
                            $gp->set_child($dir2, double_rotate($p, $last));
                        } elsif(is_red($sibling->get_child(!$last))) {
                            $gp->set_child($dir2, single_rotate($p, $last));
                        }
                        
                        #ensure correct coloring
                        my $gpc = $gp->get_child($dir2);
                        $gpc->{red} = 1;
                        $node->{red} = 1;
                        $gpc->{left}->{red} = 0;
                        $gpc->{right}->{red} = 0;
                    }
                }
            }
        }
    }
    
    #replace and remove if found
    if( defined $found ) {
        $found->{data} = $node->{data};
        $p->set_child($p->{right} && $p->{right} eq $node, $node->get_child(!defined $node->{left}));
        $this->{size}--;
    }

    #update root and make it black
    $this->{_root} = $head->{right};
    if( defined $this->{_root} ) {
        $this->{_root}->{red} = 0;
    }

    return defined $found;
}

#returns undef if tree is empty
sub min {
    my $this = shift;
    my $res = $this->{_root};
    if(!defined $res) {
        return;
    }
    
    while($res->{left}) {
        $res = $res->{left};
    }
    
    return $res->{data};
}


sub next {
    return;
    my $this = shift;
    my $elm = $this->head();
    if ( $elm->right() ) {
        $elm = $elm->right();
        while ( $elm->left() ){
            $elm = $elm->left();
        }
    } else {
        if ( $elm->parent() && 
        ( $elm == $elm->parent()->left() ) ){
            $elm = $elm->parent();
        } else {
            while ( $elm->parent() &&
            ( $elm == $elm->parent()->right() ) ){
                $elm = $elm->parent();
                $elm = $elm->parent();
            }
        }
    }
    return $elm->{data};
}

sub head { $_[0]->{_root} }

sub nfind  {
    my $this = shift;
    my $elm = shift;
    my $tmp = $this->head();
    my $res = {};
    my $comp = 0;
    
    while ($tmp) {
        $comp = $this->{_comparator}->($tmp->{data}, $elm);
        if ($comp < 0) {
            $res = $tmp;
            $tmp = $tmp->left();
        } elsif ($comp > 0) {
            $tmp = $tmp->right();
        } else {
            return $tmp->{data};
        }
    }
    return $res->{data};
}

#returns null if tree is empty
sub max {
    my $this = shift;
    my $res = $this->{_root};
    if(!$res) {
        return;
    }
    
    while( $res->{right} ) {
        $res = $res->{right};
    }
    
    return $res->{data};
}

sub single_rotate {
    my ($root, $dir) = @_;
    my $save = $root->get_child(!$dir);
    
    $root->set_child(!$dir, $save->get_child($dir));
    $save->set_child($dir, $root);
    
    $root->{red} = 1;
    $save->{red} = 0;
    return $save;
}

sub double_rotate {
    my ($root, $dir) = @_;
    $root->set_child(!$dir, single_rotate($root->get_child(!$dir), !$dir));
    return single_rotate($root, $dir);
}

package Rum::RBTree::Node; {
    use Scalar::Util 'weaken';
    use Data::Dumper;
    sub new {
        my ($class,$data) = @_;
        my $this = {};
        $this->{data} = $data;
        $this->{left} = undef;
        $this->{right} = undef;
        $this->{red} = 1;
        bless $this,$class;
    }
    
    sub get_child {
        return $_[1] ? $_[0]->{right} : $_[0]->{left};
    }
    
    sub get_right {  $_[0]->{right} }
    sub get_left  {  $_[0]->{left}  }
    
    sub set_child {
        my ($this, $dir, $val) = @_;
        if($dir) {
            $this->{right} = $val;
        } else {
            $this->{left} = $val;
        }
    }
    
    
    sub right {
        $_[0]->{right};
    }
    
    sub left {
        $_[0]->{left};
    }
    
    sub parent {
        $_[0]->{left};
    }
    
}

1;
