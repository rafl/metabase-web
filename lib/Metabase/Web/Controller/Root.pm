package Metabase::Web::Controller::Root;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller::REST' }

use Data::GUID;

__PACKAGE__->config(namespace => '');

our $VERSION = '0.001';
$VERSION = eval $VERSION; # convert '1.23_45' to 1.2345

# /submit/Test-Report/dist/RJBS/Acme-ProgressBar-1.124.tar.gz/
#  submit 0           dist 0    1
sub submit : Chained('/') Args(1) ActionClass('REST') {
  my ($self, $c, $type) = @_;

  $c->stash->{type} = $type;
}

sub submit_POST {
  my ($self, $c) = @_;

  my $struct = $c->req->data;
  my $fact_struct = $struct->{fact};
  my $submitter_struct = $struct->{submitter};

  Carp::confess("URL and POST types do not match")
    unless $c->stash->{type} eq $fact_struct->{metadata}{core}{type}[1];

  # XXX: In the future, this might be a queue id.  That might be a guid.  Time
  # will tell! -- rjbs, 2008-04-08
  my $guid = eval {
    $c->model('Metabase')->gateway->handle_submission($struct);
  };

  unless ($guid) {
    my $error = $@ || '(unknown error)';
    $c->log->error("gateway rejected fact: $error");
    my ($reason) = $error =~ /^reason: (.+)/;
    $reason ||= 'internal gateway error';
    return $self->status_bad_request($c, message => $reason);
  }

  return $self->status_created(
    $c,
    location => '/guid/' . $guid, # XXX: uri_for or something?
    entity   => { guid => $guid },
  );
}

# /guid/CC3F4AF4-0571-11DD-AA50-85A198B5225E
#  guid 0
sub guid : Chained('/') Args(1) ActionClass('REST') {
  my ($self, $c, $guid) = @_;

  if (my $guid = eval { Data::GUID->from_string($guid) }) {
    $c->stash->{guid} = $guid;
  }
}

sub guid_GET {
  my ($self, $c) = @_;

  return $self->status_bad_request($c, message => "invalid guid")
    unless my $guid = $c->stash->{guid};

  return $self->status_not_found($c, message => 'no such resource')
    unless my $fact = $c->model('Metabase')->librarian->extract($guid);

  return $self->status_ok(
    $c,
    entity => $fact->as_struct,
  );
}

# /search/.....
sub search : Chained('/') CaptureArgs(0) {
}

sub simple : Chained('search') ActionClass('REST') {
}

sub simple_GET {
  my ($self, $c, @args) = @_;

  my $data = $c->model('Metabase')->librarian->search(@args);

  return $self->status_ok(
    $c,
    entity => $data,
  );
}

__PACKAGE__->meta->make_immutable;

1;
