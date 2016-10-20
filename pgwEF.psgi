
my $ecUser   = "admin";
my $ecPasswd = "changeme";

my $ghSecret = "Mgimp,vm";

use Data::Dumper;
use JSON;

use XML::XPath;

# locate ElectricCommander packages
use lib 'ElectricCommander-6.0300/lib';
use ElectricCommander;

$| = 1;

my $ec;

if ( defined $ENV{COMMANDER_SERVER} ) {
  $ec = new ElectricCommander->new();
  $ec->abortOnError(0);
} else {
  print "COMMANDER_SERVER not set \n";
  exit 1;
}

if ( !$ENV{'COMMANDER_SESSIONID'} ) {
  my $L = $ec->login( $ecUser, $ecPasswd );
  if ( "1" ne $L->findvalue('//response/@requestId') ) {
    print "FAIL: ", $L->findnodes_as_string("/");
    exit 1;
  }
}

sub ghLog ($) {
  ($msg) = @_;
  open DEBUG, '>>', "pgw-hook.log" or die $!;
  print DEBUG "$msg\n";
  close DEBUG;
}

sub ghRunSchedule ($$$) {
  my ( $ghRepo, $ghBranch, $ghSha ) = @_;

  my @filterList;
  push(
    @filterList,
    {
      "propertyName" => "github_branch",
      "operator"     => "equals",
      "operand1"     => $ghBranch
    } );
  push(
    @filterList,
    {
      "propertyName" => "github_repo",
      "operator"     => "equals",
      "operand1"     => $ghRepo
    } );
  push(
    @filterList,
    {
      "propertyName" => "github_status",
      "operator"     => "equals",
      "operand1"     => "1"
    } );

  my $xPath = $ec->findObjects(
    "schedule",
    {
      maxIds     => "10",
      numObjects => "2",
      filter     => \@filterList
    } );

  # Loop over all returned schedules
  my $projectName  = "";
  my $scheduleName = "";
  my $nodecount    = 0;
  my $nodeset      = $xPath->find('//schedule');
  foreach my $node ( $nodeset->get_nodelist ) {
    $nodecount++;
    $projectName  = $xPath->findvalue( 'projectName',  $node );
    $scheduleName = $xPath->findvalue( 'scheduleName', $node );
  }
  if ( $nodecount == 1 ) {
    #ghLog ("$projectName $scheduleName\n");
    my $xpath = $ec->setProperty(
      "github_last_ci_sha",
      {
        projectName  => $projectName,
        scheduleName => $scheduleName,
        value        => "$ghSha",
      },
    );

    my $xpath =
      $ec->runProcedure( $projectName, { scheduleName => $scheduleName, } );
    ghLog( $xpath->findvalue("//jobId")->string_value . "\n" );
    #ghLog ($xpath->findnodes_as_string("/"));
  } else {
    ghLog("There were $nodecount schedules returned for:");
    ghLog(" ghRepo:$ghRepo");
    ghLog(" ghBranch:$ghBranch");
  }
  #ghLog ($xPath->findnodes_as_string("/"));
}

# locate plack packages
use lib 'lib';
use Plack::App::GitHub::WebHook;

my @ghHookCode;
push(
  @ghHookCode,
  sub {
    my ( $payload, $event, $delivery, $log ) = @_;
    open DEBUG, '>', "payload.perl" or die $!;
    print DEBUG Dumper($payload);
    close DEBUG;
    open DEBUG, '>', "payload.json" or die $!;
    print DEBUG to_json($payload);
    close DEBUG;
    if ( "push" eq $event ) {
      my $branch = $payload->{ref};
      $branch =~ s/refs\/heads\///;
      ghLog(
        "$delivery,$event,$payload->{repository}->{url},$branch,$payload->{commits}[0]->{id}"
      );
      ghRunSchedule( $payload->{repository}->{url}, $branch, $payload->{commits}[0]->{id} );
    } elsif ( "ping" eq $event ) {
      ghLog("$delivery,$event,$payload->{hook}->{url}");
    } else {
      ghLog(
        "Error: Unsupported event ($event) for $delivery of $payload->{hook}->{url}"
      );
    }
  } );

Plack::App::GitHub::WebHook->new(
  hook   => \@ghHookCode,
  secret => $ghSecret,
  access => 'all',
)->to_app;

#
#access => 'github',
#
#access => [
#    allow => "204.232.175.64/27",
#    allow => "192.30.252.0/22",
#    ...
#]
##access => [
#    allow => "204.232.175.64/27",
#    allow => "192.30.252.0/22",
#    allow => "localhost",
#    ...
#]
#
#access => 'all'
#access => []
#
