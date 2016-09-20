package TTPlugins::Animal;

use strict;

use base qw( TTPlugins::Base );

##

sub answers {
    my($self, $start, $size) = @_;
    my $dbh = $self->dbh;

    my $query = ("SELECT * FROM answer ORDER BY date DESC "
		 . "LIMIT $size OFFSET $start"
		);
    my $sth = $dbh->prepare($query);
    $sth->execute;

    my @result;
    while(my $row = $sth->fetchrow_hashref) {
	push @result, $row;
    }

    return \@result;
}

##

1;
