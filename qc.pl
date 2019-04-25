#!/usr/bin/perl -w
use strict;
use LWP::Simple;
use Getopt::Long;
use JSON;
use JSON::Parse 'parse_json';
use HTML::Make;
use File::Copy;
use File::Basename;

my ($lib_csv) = shift or die "perl $0 <lib csv>\n";

my %lib_info = read_csv($lib_csv); 

# check header in the lib csv
# Sample	Project	Barcode_number	Barcode_id	i7	i5	Barcode_source
my @header_required = qw(Sample	Project	Barcode_number	Barcode_id	i7	i5	Barcode_source);
my @missed_header = ();
map{
    push @missed_header, $_ unless exists $lib_info{$_}
}@header_required;
if(@missed_header){ print STDERR "Error: some of the headers are missing:", join(",", @missed_header), "\n"; exit }

$lib_info{"Barcode_source"} = [map{uc $_} @{$lib_info{"Barcode_source"} }];

my %lib_info_zip = zip(@lib_info{4, @header_required}); # 4 indicate Barcode_id will be the key for hash

# load the barcode csv files
my %barcodes = load_barcodes();
my %barcodes_zip;
map{
    $barcodes_zip{$_} = zip(2, @barcodes{qw(Number	Id	i7	i5)})
}keys %barcodes;
# Check
my $output = "/tmp/" . random_str() . ".html";
open(my $OUT, $output) or die $!;
# a)	Will check for consistency Id vs Name vs Position in Plate
## ids
my @tobe_checked;
foreach my $k (keys %lib_info_zip){
    my @arr = @{$lib_info_zip{$k}};
    if (not exists $barcodes_zip{$arr[-1]}) {
        print STDERR "Error: $arr[-1] is not one of the (neb_CDI perkin_HT_S1 perkin_UDI perkin_UDI_4K txgen_combo)!"; 
        exit;
    }
    my @results;
    if ($arr[2] == $barcodes_zip{$arr[-1]}->{$k}->[0]){push @results, "Index number matching"}else{push @results, "Index number NOT matching"}
    if ($arr[4] == $barcodes_zip{$arr[-1]}->{$k}->[2]){push @results, "i7 matching"}else{push @results, "i7 NOT matching"}
    if ($arr[5] == $barcodes_zip{$arr[-1]}->{$k}->[3]){push @results, "i5 matching"}else{push @results, "i5 NOT matching"}
    print $OUT "<p>", join(",", @arr, @results), "</p>\n";
    push @tobe_checked, [uc $arr[4], uc $arr[5]];
}

# b)	Will check for barcode compatibility (with extension to 12+8 optional)
my @conflicts = check_barcodes(\@tobe_checked);
if (@conflicts){
    print $OUT "<a style=\"color:red\">There are conflicts detected!!</a><br>\n";
    my $json = to_json(@conflicts);
    my $p = parse_json($json);
    my $html = json_to_html($p);
    print $OUT $html->text();
}

# c)	Will generate report to download
print $OUT "Report: ", "http://download.txgen.tamu.edu/shichen/".basename($output);
close $OUT;

my $new_file = "/home/shichen.wang/for_down/" . basename($output);
copy($output, $new_file) or die "Copy failed: $!";
print "Report: ", "http://download.txgen.tamu.edu/shichen/".basename($output);


######
sub load_barcodes {
    my $neb_CDI  = "https://raw.githubusercontent.com/swang8/barcodes/master/NEB_NEXT_CDI_Combined.csv";
    my $perkin_HT_S1 = "https://raw.githubusercontent.com/swang8/barcodes/master/PerkinElmer_NextFlex_HT_SI.csv";
    my $perkin_UDI = "https://raw.githubusercontent.com/swang8/barcodes/master/PerkinElmer_NextFlex_UDI.csv";
    my $perkin_UDI_4k = "https://raw.githubusercontent.com/swang8/barcodes/master/PerkinElmer_NextFlex_UDI_4000.csv";
    my $txgen_combo = "https://raw.githubusercontent.com/swang8/barcodes/master/TxGen_DuLig_CDI_Combined.csv";
    my %h;
    @h{map{uc $_}qw(neb_CDI perkin_HT_S1 perkin_UDI perkin_UDI_4K txgen_combo)} = 
                ($neb_CDI, $perkin_HT_S1, $perkin_UDI, $perkin_UDI_4k, $txgen_combo);
    my %return;
    map{
        my %info = read_csv($h{$_});
        $return{$_} = \%info;
    }keys %h;
    return %return;
}

sub get_barcode_file {
    my $url = shift;
    my $file = (split /\//, $url)[-1];
    getstore($url, "/tmp/" . $file);
}

sub read_csv {
    my $f = shift;
    print STDERR "CSV: ", $f, "\n";
    my $IN;
    if ($f=~/http/){open($IN, "wget -O- -nv $f |") or die $!}
    else{open($IN, $f) or die "$f is not readable!\n";}
    
    my %return;
    my @header;
    my $line = 0;
    while(<$IN>){
        next if /^\#/;
        chomp;
        s/\,+$//;
        next unless /\S/;
        $line++;
        my @t = split /,/, $_;
        if ($line == 1){@header = @t; print STDERR "Header: ", $_, "\n"; next}
        map{
            push @{$return{$header[$_]}}, $t[$_]
        }0..$#t;
    }
    close $IN;
    return %return;
}

sub zip {
    my $k = shift;
    my @arr = @_;
    my @len = map{scalar @$_; }@arr;
    my $max_len = max(@len);
    my %return;
    map{
        my $index = $_;
        my @z = ();
        foreach my $ref (0 .. $#arr){
            if ($index > $len[$ref] - 1) {$index = $len[$ref] - $index}
            push @z, $arr[$ref]->[$index]
        }
        $return{$z[$k-1]} = [@z]
    } 0 .. $max_len - 1;

    return %return;
}

sub max {
    my @arr = @_;
    my $m = shift @arr;
    map{$m = $_ if $_ > $m}@arr;
    return $m;
}

sub random_str {
    my $l = shift || 8;
    my @letters=('a..z', 'A..Z', 0..9);
    my $return="";
    map{$return .= $letters[int(rand(scalar @letters))]}1..$l;
    return $return
}

sub check_barcodes{
  my $arr_ref = shift;
  my $cutoff = shift;
  $cutoff = 3 unless $cutoff;
  my @arr = @$arr_ref;
  # checking
  my %dist = calculate_distance(@arr);
  my @conflict=();
  foreach my $ind1 (0 ..$#arr){
    my @ba = @{$arr[$ind1]};
    my $type_a = scalar @ba == 1?"single":"double";
    my @conf=();
    foreach my $ind2 ($ind1+1 .. $#arr){
      my @bb = @{$arr[$ind2]};
      my $type_b = scalar @bb == 1?"single":"double";
      if($type_a eq "single" or $type_b eq "single"){
        my $id = join(" ", sort{$a cmp $b}($ba[0], $bb[0]) );
        # print STDERR $id, "\t", $dist{$id}, "\n";
        if (! exists $dist{$id}){die "$id not in \%dist\n"}
        if($dist{$id} < $cutoff){
            push @conf, join("_", @{$arr[$ind2]}, $dist{$id});
        }
      }else{
        my $id0 = join(" ", sort{$a cmp $b}($ba[0], $bb[0]) );
        my $id1 = join(" ", sort{$a cmp $b}($ba[1], $bb[1]) );
        #print STDERR $id0, "\t", $dist{$id0}, "\n";
        #print STDERR $id1, "\t", $dist{$id1}, "\n";
        if($dist{$id0} < $cutoff and $dist{$id1} < $cutoff){
            push @conf, join("_", @{$arr[$ind2]}, $dist{$id0}, $dist{$id1});
        }
      }
    }
    push @conflict, {"barcode"=>join("_", @{$arr[$ind1]}), "potential_conflict"=>join(",", @conf)} if @conf > 0;
  }
  return @conflict;
}

sub calculate_distance{
  my @arr = @_;
  my @flat = map{@$_}@arr;
  @flat = unique(@flat);
  my %dist = ();
  foreach my $ka (@flat){
      foreach my $kb (@flat){
          my $id = join(" ", sort{$a cmp $b}($ka, $kb));
          next if exists $dist{$id};
          if($ka eq $kb){$dist{$id} = 0; next}
          my $min_len = length $ka > length $kb?(length $kb):(length $ka);
          my $d = 0;
          foreach my $ind (0..$min_len-1){$d++ if substr($ka, $ind, 1) ne substr($kb, $ind, 1) }
          $dist{$id}=$d
      }
  }
  return %dist;
}

sub unique{
  my @arr =@_;
  my %h = map{$_, 1 if /\S/}@arr;
  return keys %h;
}

sub json_to_html
{
    my ($input) = @_;
    my $element;
    if (ref $input eq 'ARRAY') {
        $element = HTML::Make->new ('ol');
        for my $k (@$input) {
            my $li = $element->push ('li');
            $li->push (json_to_html ($k));
        }
    }
    elsif (ref $input eq 'HASH') {
        $element = HTML::Make->new ('table');
        for my $k (sort keys %$input) {
            my $tr = $element->push ('tr');
            $tr->push ('th', text => $k);
            my $td = $tr->push ('td');
            $td->push (json_to_html ($input->{$k}));
        }
    }
    else {
        $element = HTML::Make->new ('span', text => $input);
    }
    return $element;
}