#!/usr/local/ensembl/bin/perl

=head1 NAME

  dump_translations.pl

=head1 DESCRIPTION

  It's a stripped down version of gene2flat. The script dumps out the
  translations for all protein coding transcripts in a database. Note
  that sequences are identified by their transcript identifiers and
  not their translation identifiers.

=head1 SYNOPSIS

  dump_translations.pl

  Required arguments:

    -dbname       Database name
    -dbhost       Database server host
    -dbport       Database server port
    -dbuser       Database user
    -dbpass       User password
    -stable_id    Outputs sequences identified with their stable IDs
    -db_id        Outputs sequences identified with their internal identifier.
                  The db_id and stable_id flags are mutually exclusive.

  Optional arguments:

    -file         File to write the results to (default: STDOUT)
    -slicename    Retrieve sequences from this slice
    -dnadbname    DNA database name
    -dnadbhost    DNA database server host
    -dnadbport    DNA database server port
    -dnadbuser    DNA database user
    -dnadbpass    DNA user password
    -verbose      Verbose logging (default: false)

=cut

use strict;
use warnings;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::SeqIO;
use Getopt::Long;

my $dbname = '';
my $dbhost = '';
my $dbuser = 'ensro';
my $dbport = 3306;
my $dbpass = undef;

my $dnadbname = '';
my $dnadbhost = '';
my $dnadbuser = 'ensro';
my $dnadbport = 3306;
my $dnadbpass = undef;

my $stable_id = 0;
my $db_id     = 0;
my $file;
my $slicename;
my $verbose;

GetOptions(
    'dbhost=s'    => \$dbhost,
    'dbname=s'    => \$dbname,
    'dbuser=s'    => \$dbuser,
    'dbpass=s'    => \$dbpass,
    'dbport=s'    => \$dbport,
    'dnadbhost=s' => \$dnadbhost,
    'dnadbname=s' => \$dnadbname,
    'dnadbuser=s' => \$dnadbuser,
    'dnadbport=s' => \$dnadbport,
    'dnadbpass=s' => \$dnadbpass,
    'stable_id!'  => \$stable_id,
    'db_id!'      => \$db_id,
    'file=s'      => \$file,
    'slicename=s' => \$slicename,
    'verbose'     => \$verbose,
) or die("Couldn't get options");

die("need to pass database settings in on the commandline -dbhost -dbuser -dbname -dbpass")
  if not $dbhost
      or not $dbname;

die "need to specify to use either stable_id or dbId for the header line"
  if not defined $stable_id and not defined $db_id;

if ($stable_id and $db_id) {
    $verbose and print STDERR "Entry ids will be db_id.stable_id\n";
}
elsif ($stable_id) {
    $verbose and print STDERR "Entry ids will be translation stable_ids\n";
}
else {
    $verbose and print STDERR "Entry ids will be translation dbIDs\n";
}

my $db;

if ($dnadbname) {
    if (not $dnadbhost or not $dnadbuser) {
        die "Fine. Your DNA is not in '$dbname' but in '$dnadbname'. But you must give a user and host for it\n";
    }

    my $dnadb = new Bio::EnsEMBL::DBSQL::DBAdaptor(
        '-host'   => $dnadbhost,
        '-user'   => $dnadbuser,
        '-dbname' => $dnadbname,
        '-pass'   => $dnadbpass,
        '-port'   => $dnadbport,
    );

    $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
        '-host'   => $dbhost,
        '-user'   => $dbuser,
        '-dbname' => $dbname,
        '-pass'   => $dbpass,
        '-port'   => $dbport,
        '-dnadb'  => $dnadb,
    );
}
else {
    $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
        '-host'   => $dbhost,
        '-user'   => $dbuser,
        '-dbname' => $dbname,
        '-pass'   => $dbpass,
        '-port'   => $dbport,
    );
}

my $fh;
if ($file) {
    $verbose and print STDERR "Going to write peptides to '$file'\n";
    open(FH, '>' . $file) or die "couldn't open file " . $file . " $!";
    $fh = \*FH;
}
else {
    $verbose and print STDERR "Going to write peptides to stdout\n";
    $fh = \*STDOUT;
}

my $seqio = Bio::SeqIO->new('-format' => 'Fasta', -fh => $fh);

my $gene_list;

if (defined $slicename) {
    my $slice = $db->get_SliceAdaptor->fetch_by_name($slicename);
    $gene_list = $slice->get_all_Genes;
}
else {
    my $gene_adaptor = $db->get_GeneAdaptor();
    my $gene_ids     = $gene_adaptor->list_dbIDs();
    $gene_list = $gene_adaptor->fetch_all_by_dbID_list($gene_ids);
}

# shift the next gene off the list, or the memory used by this script will grow
# and grow as gene components are fetched from the database.
while (my $gene = shift @$gene_list) {
    my $gene_id = $gene->dbID();

    foreach my $trans (@{ $gene->get_all_Transcripts }) {
        next if (!$trans->translation);

        my $identifier;
        if ($db_id) {
            $identifier = $trans->translation->dbID;
        }
        if ($stable_id) {
            if (!$db_id) {
                $identifier = $trans->stable_id;
            }
            else {
                $identifier .= "." . $trans->stable_id;
            }
        }
        my $tseq = $trans->translate();
        if ($tseq->seq =~ /\*/) {
            print STDERR "Translation of $identifier has stop codons ",
              "- Skipping! (in ", $trans->slice->name(), ")\n";
            next;
        }

        $tseq->display_id($identifier);
        $tseq->desc("Translation id $identifier gene $gene_id");
        $seqio->write_seq($tseq);
    }
}
close($fh) or die "Error writing translation fasta; $!";