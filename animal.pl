#!/usr/bin/perl -w

package animal;

# $Revision: 1.10 $

use strict;
use CGI;

use HTTP::Daemon;
use HTTP::Status;
use HTTP::Response;
use Inline WebChat => 'DATA';
use DBI;
use Net::SMTP;
use MIME::QuotedPrint;

use Data::Dumper;

use Template;

use Class::MethodMaker 
  new => 'new',
  get_set => [qw/ q data redirect proprietry start_time todo /];

$SIG{PIPE} = sub {};

#make_schema();

{
    my $self = __PACKAGE__->new;

    $self->init;

    eval {
	$self->serve;
    };
    if ($@) {
	warn("oops: $@\n");
    }
}

sub plan {
    my $self = shift;
    $self->{plan} ||= 
      {
       friendly_lists =>
       {action   => 'submit_to_mailing_list',
	to       => {
		     '(void)ers'   => 'void@slab.org',
		     'london dorkbotters' => 
		     'dorkbotlondon-blabber@dorkbot.org',
		     'nyc dorkbotters' => 
		     'dorkbotnyc-blabber@dorkbot.org',
		     slobbers      => 'slobber@slab.org',
		     'eu-gene-ers' => 'eu-gene@generative.net',
		     'linart people' => 'linart@li.org',
		    },
	template => 'invite',
	when => {days_old => 1}
       },
       ntk =>
       {action   => 'submit_to_mailing_list',
	to       => {ntk => 'tips@spesh.com'},
	template => 'ntk',
	when => {days_old => 3}
       },
       test =>
       {action   => 'submit_to_mailing_list',
	to       => {test => 'test@slab.org'},
	template => 'ntk',
	when => {days_old => 0}
       },
       # second wave of mailing list posts
       rhizome =>
       {
	action   => 'submit_to_mailing_list',
	to       => {rhizomers => 'list@rhizome.org'},
	from     => 'rhizome-raw@lurk.org',
	template => 'self_publicity',
	when => {
		 respondents => 20,
		 # or
		 days_old => 7
		},
       },
       nettime =>
       {
	action   => 'submit_to_mailing_list',
	to       => {nettimers => 'nettime-l@bbs.thing.net'},
	template => 'self_publicity',
	when => {
		 respondents => 20,
		 # or
		 days_old => 7
		},
       },
       slashdot => 
       {
	action   => 'submit_to_slashdot',
	when => {
		 respondents => 50,
		 # or
		 days_old => 14
		},
       },
       boingboing => 
       {
       action   => 'submit_to_boingboing',
       when => {
		respondents => 25,
		 # or
		 days_old => 7
		},
       },
       release =>
       {
	action   => 'gpl_myself',
	post_trigger  => ['list_expose', 'list_expose2'],
	when     => {days_old => 28},
       },
       list_expose =>
       {
	action   => 'submit_to_mailing_list',
	to       => {'eu-gene'      => 'eu-gene@generative.net',
		     'bot people' => 'bots@london.pm.org',
		     'linart people' => 'linart@li.org',
		     '(void)ers'   => 'void@slab.org',
		     'london dorkbotters' => 
		     'dorkbotlondon-blabber@dorkbot.org',
		     'nyc dorkbotters' => 
		     'dorkbotnyc-blabber@dorkbot.org',
		    },
	template => 'expose',
       },
       # second wave of mailing list posts
       list_expose2 =>
       {
	action   => 'submit_to_mailing_list',
	to       => {rhizomers => 'list@rhizome.org'},
	from     => 'rhizome-raw@lurk.org',
	template => 'expose'
       },
      };
}

##

sub root {
    '/home/alex/animal';
}

##

sub address {
    'lurk.org'
}

##

sub port {
    80
}

##

sub gpl_myself {
    my $self = shift;
    my $gpl_header = $self->template('gpl',
				     {name => 'alex <alex@slab.org>'}
				    );
    print("opening $0\n");
    open(FH, "<$0")
      or die("couldn't read myself");
    my $code = join('', <FH>);
    close FH;

    $code =~ s,^(\#!/usr/bin/perl.+),$1\n\n$gpl_header,;

    open(FH, ">$0")
      or die("couldn't change myself");
    print(FH $code);
    close FH;

    system("cvs commit -m 'placed myself under the GNU Public License' $0");

    $self->proprietry(0);
}

##

sub url {
    my $self = shift;
    my $address = $self->address;
    return("http://$address/");
}

##

sub serve {
    my $self = shift;
    my $tt = $self->tt;
    my $d = HTTP::Daemon->new(LocalAddr => $self->address, 
			      LocalPort => $self->port,
			      Reuse => 1,
			      Listen => 5 # TODO
			     )
      or die "Couldn't start httpd: $!";
    print "listening on ", $d->url, "\n";

    my $dbh = $self->dbh;
    my $hits = 0;

    while (1) {
	if (not (++$hits % 100)) {
	    $self->logit("total hits: $hits\n");
	}
	my $c = $d->accept;

	my $r = $c->get_request;

	if (not $r) {
	    # randal's code said to do this
	    $c->close;
	    next;
	}
	eval {
	    my $uri = $r->uri;
	    my $q = CGI->new($r->url->query);
	    $self->q($q);
	    my $data = {dbh        => $dbh,
			c          => $c,
			q          => $q,
			proprietry => $self->proprietry,
			url        => $self->url
		       };
	    $self->data($data);
	    $self->actions();
	    if ($self->redirect) {
		$c->send_redirect($self->redirect);
	    }

	    my $output = '';
	    if ($uri =~ m,^/source/,) {
		$uri =~ s,^/source,,;
		die "bad uri" if $uri =~ /\.\./;
		my $file = $self->root . $uri;
		if (-d $file) {
		    my %files;
		    $output .= CGI::header();
		    opendir(DIR, $file)
		      or die "couldn't read '$file'";
		    foreach my $subfile (readdir(DIR)) {
			next if $subfile =~ /^\./;
			if (-d $file . $subfile) {
			    $files{$subfile} = 'directory'
			}
			else {
			    $files{$subfile} = 'file'
			}
		    }
		    closedir(DIR);
		    $output .= $self->template('directory',
					       {name  => $uri,
						files => \%files
					       }
					      );
		}
		else {
		    $output .= CGI::header('text/plain');
		    open(FH, "<$file")
		      or die("couldn't open $file: $!");
		    $output .= join('', <FH>);
		    close(FH);
		}
	    }
	    else {
		my $tt = $self->tt;
		my ($path) = ($r->url->path() =~ /^\/(.*)/);
		$path ||= 'index.html';
		$path =~ s,/$,/index.html,;
		$tt->process($path, $data, \$output)
		  || die $tt->error();
		$output = CGI::header() . $output;
	    }

	    $c->send_basic_header;
	    print $c $output;
	};
	if ($@) {
	    warn($@);
	    $c->send_error(RC_FORBIDDEN)
	}
	
	$c->close;
	$self->redirect(undef);
	$self->data(undef);

	$self->do_todos();
    }
}

##

sub template {
    my ($self, $template_name, $data) = @_;

    my $output;
    $data ||= {};
    my $tt = $self->tt;

    $tt->process($template_name, $data, \$output)
      or die $tt->error();

    return $output;
}

##

sub actions {
    my($self) = @_;
    my $q = $self->q;
    foreach my $action ($q->param('action')) {
	$self->logit("action: $action");
	my $func = "action__$action";
	if ($self->can($func)) {
	    $self->$func();
	}
	else {
	    die("no action '$action'");
	}
    }
}

##

sub action__test {
    my ($self, $data) = @_;
    $data->{thing} = 'bang';
}

##

sub action__answer {
    my ($self) = @_;
    my $q = $self->q;
    my $answer = $q->param('answer');
    $answer =~ s/^\s+//;
    $answer =~ s/\s+$//;
    if (not $answer) {
	$self->data->{error_answerless};
    }
    else {
	my $dbh = $self->dbh;
	my @fields = ('answer', 'name', 'url', 'location');
	my $query = ('insert into answer '
		     . '(date, '
		     . join(', ', @fields) 
		     . ') values ('
		     . $dbh->quote(scalar(time))
		     . ', '
		     . join(', ', map {$dbh->quote($q->param($_))} @fields)
		     . ')'
		    );
	$dbh->do($query);
	$self->redirect('thanks.html');
    }
}

##

sub respondents {
    my $self = shift;

    my ($count) = $self->dbh->selectrow_array("select count(*) from answer");

    return $count;
}

##

{
    my $tt;
    sub tt {
	my $self = shift;
	$tt ||= 
	  Template->new({
			 INCLUDE_PATH => $self->root . '/templates',
			 COMPILE_DIR  => $self->root . '/.template_cache',
			 #FILTERS     => ($self->filters || {}),
			 PLUGIN_BASE => 'TTPlugins',
			}
		       )
	    || die $tt->error(), "\n";
	;
    }
}

##

sub submit_to_usenet {
    my $self = shift;

    # TODO: google?
}

##

sub make_schema {
    my $db = dbh();
    $db->do("drop table answer");
    $db->do("create table answer (
             answer text,
             name   text,
             url    text,
             location text,
             date   text
             );"
	   );

}

##

{
    my $dbh;
    sub dbh {
	if (not $dbh) {
	    my $dbname = root() . '/db';
	    $dbh = DBI->connect("dbi:SQLite:dbname=$dbname","","");
	}
	return $dbh;
    }
}

##

sub submit_to_mailing_list {
    my ($self, $p) = @_;

    my $template_p = {url          => $self->url,
		      days_old     => $self->days_old,
		      respondents  => $self->respondents
		     };

    while (my ($name, $address) = each %{$p->{to}}) {
	$template_p->{name} = $name;
	$self->mail({to => $address,
		     from => 'alex@slab.org',
		     template => $p->{template},
		     template_p => $template_p
		    }
		   );
    }
}

##

sub mail {
    my ($self, $p) = @_;
    $p ||= {};

    my $to         = ($p->{to}         or die "no to"       );
    my $from       = ($p->{from}       or die "no from"     );
    my $bounce     = ($p->{bounce}     or $from             );
    my $reply_to   = ($p->{reply_to}   or undef             );
    my $subject    = ($p->{subject}    or "animal"          );
    my $template   = ($p->{template}   or die "no template" );
    my $template_p = ($p->{template_p} or {}                );
    my $tt         = $self->tt;

    $template = "mail/$template";

    my $body;
    my $result;
    if ($template) {
	$result = $tt->process($template, $template_p, \$body);
	if (not $result) {
	    die("tt->process($template) failed: " . $tt->error);
	}
    }
    else {
	die "Nothing to send!";
    }

    if ($body =~ s/^Subject:\s*([^\n]+)\n//s) {
	$subject = $1;
    }

    $body =~ s/\r//g;
    $body = encode_qp($body);

    my $smtp = Net::SMTP->new('smtphost')
    or die "Couldn't open smtp: $!\n";

    # sorry about the mess..
    $smtp->mail($bounce)
      or die "smtp error $!";
    $smtp->to($to)
      or die "smtp error: badly formed email '$to': $!";
    $smtp->data
      or die "smtp error $!";
    $smtp->datasend("To: $to\n")
      or die "smtp error $!";
    $smtp->datasend("From: $from\n")
      or die "smtp error $!";
    if($reply_to) {
	$smtp->datasend("Reply-To: $reply_to\n")
	  or die "smtp error $!";
    }
    $smtp->datasend("Subject: $subject\n"
		    . "MIME-Version: 1.0\n"
		    . "Content-Type: text/plain; charset=\"iso-8859-1\"\n"
		    . "Content-Transfer-Encoding: quoted-printable\n"
		    . "\n"
		   )
      or die "smtp error $!";

    $smtp->datasend("$body\n")
      or die "smtp error $!";
    $smtp->dataend()
      or die "smtp error $!";
    $smtp->quit
      or die "smtp error $!";

    return 1;
}

##

sub init {
    my $self = shift;
    $self->todo([keys %{$self->plan}]);
    $self->start_time(time());
    $self->proprietry(1);
    $self->logit("initialised");
}

##

sub days_old {
    my $self = shift;
    return(int((time() - $self->start_time) / (60 * 60 * 24)));
}

##

sub todo_now {
    my $self = shift;

    my $plan = $self->plan;

    my $respondents = $self->respondents;
    my $days_old = $self->days_old;
    my %result;
    my @keys = keys %$plan;
    while(my $key = shift @keys) {
	next if not exists $plan->{$key};

	my $hash = $plan->{$key};
	my $when = $hash->{when};
	next if not defined $when;
	if ((defined($when->{days_old})
	     and $when->{days_old} <= $days_old
	    )
	    or
	    (defined($when->{respondents})
	     and $when->{respondents} <= $respondents
	    )
	   ) {

	    delete $plan->{$key};
	    $result{$key} = $hash;
	    if ($hash->{post_trigger}) {
		foreach my $post_trigger (@{$hash->{post_trigger}}) {
		    next if not exists $plan->{$post_trigger};
		    $result{$post_trigger} = $plan->{$post_trigger};
		    delete $plan->{$post_trigger};
		}
	    }
	}
    }

    return \%result;
}

##

sub do_todos {
    my $self = shift;
    my $todo_now = $self->todo_now;
    while (my($todo, $hash) = each %$todo_now) {
	$self->logit("doing $todo");
	my $action = $hash->{action};
	if(not $action) {
	    warn("no action for $todo!\n");
	    next;
	}
	if (not $self->can($action)) {
	    warn("can't find method '$action'\n");
	    next;
	}
	$self->$action($todo_now->{$todo});
    }
}

##

sub logit {
    my($self, $text) = @_;
    my @t = localtime();
    $t[4] += 1900;
    my $days_old = $self->days_old;
    warn(sprintf("[day %d, %02d:%02d:%02d] %s",
		 $days_old, $t[2], $t[1], $t[0], $text
		)
	);
}

##

__DATA__
__WebChat__

sub submit_to_slashdot {
    my $self = shift;
    my $page;

    GET http://slashdot.org/submit.pl
    EXPECT OK
      FORM:2
      F email = 'alex-slashdot@slab.org';
      F story = $self->template('slashdot/story');
      F subj  = 'Arbitrary book excerpts';
      SUBMIT
       FORM:2
       F op=SubmitStory
       SUBMIT
         $page = $_;
       BACK
      BACK
    BACK
    return $page;
}

##

sub submit_to_boingboing {
    my $self = shift;
    my $page;

    GET http://boingboing.net/suggest.html
    EXPECT OK
      FORM:1
      F email_name    = 'alex';
      F email_from    = 'alex-boingboing@slab.org';
      F from_url      = 'http://slab.org';
      F subject       = 'Algorithm for distributed random book excerpts';
      F suggested_url = $self->url;
      F description   = $self->template('boingboing/story');
      SUBMIT
    BACK
    return $page;
}

