#!/usr/bin/perl

# Madelaine Gogol 
# originally written 10/22/2009
# inspired by "splitter" peak caller with a simple threshold.
# original splitter: https://zlab.bu.edu/yf/anchor/web/splitter.cgi?step=0
# Example call: perl mysplitter.pl mytrack.bedGraph 10 300 2
# where 10 is minimum run, 300 is the maximum gap between data, and 2 is the threshold (threshold can also be given as percentile like 95pct).

use File::Basename;
use POSIX;

my ($pos_of_value_above_threshold,$overallthresh,$peakid,$chrom, $build, $threshold,$file,$minrun,$maxgap);




if (@ARGV) 
{
	($file, $minrun, $maxgap, $threshold, $overallthresh) = @ARGV;

	$shortfile = basename($file);
	$shortfile =~s/\.wig//g;
	open(LOG,">mysplitter.$shortfile.log");
	print LOG "file: $file\nminrun: $minrun\nmaxgap: $maxgap\nthreshold $threshold\n";


	#deal with calling the threshold based on a percentile
	if($threshold =~ /pct$/)
	{
		$orig = $threshold;
		$threshold =~ s/pct//g;
		$wc = `wc -l $file`;
		$wc =~ s/\s.*//g;
		$line = floor($wc * $threshold / 100);
		print LOG "line should be $line wc:$wc pct:$threshold\n";
		`cut -f 4 $file | sort -n > $file.sort`;
		$cmd = "sed -n ".$line."p $file.sort";
		$result = `$cmd`;
		chomp $result;
		$result =~ s/^0//g;
		print LOG "threshold calced:$result:\n";
		$threshold = sprintf("%.2f",$result);
		`rm $file.sort`;
		open(BED,">peaks_$shortfile.$minrun.$maxgap.$threshold.$orig.bed");
		print BED "track name=peaks_$shortfile.$minrun.$maxgap.$threshold.$orig useScore=1 priority=2\n";
	}
	else #user given threshold
	{
		open(BED,">peaks_$shortfile.$minrun.$maxgap.$threshold.bed");
		print BED "track name=peaks_$shortfile.$minrun.$maxgap.$threshold useScore=1 priority=2\n";
	}

	print LOG "file: $file\nminrun: $minrun\nmaxgap: $maxgap\nthreshold $threshold\n";
}



open IN, $file or die "can't open file $file, $!\n";
$last_chrom = "chr";
$build = 0;
$peakid = 1;
while (<IN>) 
{
	print LOG "in file\n";
	$_ =~ s/[\n\r]//g;
	if ($_ =~ /^(track name=\S+)/) 
	{
		#track line, ignore
	} 
	else
	{
		my ($chrom, $start, $end, $value) = split /\t/, $_;
		print LOG "start:$start:\n";
		print LOG "val:$value:\n";
		
		#find peaks here
		if($last_chrom eq $chrom)
		{
			if($build == 0 and $value > $threshold)
			{	
				#start a peak... keep building until you can't find any more within maxgap.
				$endpoint = $end + $maxgap;
				push(@mypeakstarts,$start);
				push(@mypeakends,$end);
				push(@mypeakvals,$value);
				$pos_of_value_above_threshold = $end;
				print LOG "starting peak $chrom $start $value $endpoint\n";
				$build = 1;
			}
			elsif($build == 0 and $value <= $threshold)
			{
				#keep going, do nothing.
				print LOG ".";
			}
			elsif($build == 1 and $value > $threshold)
			{
				if($start < $endpoint)
				{
					#add to peak
					print LOG "adding to peak $chrom $start $value\n";
					$endpoint = $end + $maxgap;
					push(@mypeakstarts,$start);
					push(@mypeakends,$end);
					push(@mypeakvals,$value);
					$pos_of_value_above_threshold = $end;
				}
				if($start >= $endpoint)
				{
					#finish peak and start a new peak
					if($#mypeakstarts+1 >= $minrun)
					{
						print LOG "finishing peak $last_chrom $mypeakstarts[0] $mypeakends[$#mypeakends] $peakval\n";
						$peakval = median(@mypeakvals) * 1000;
						if($peakval > $overallthresh)
						{
							$tempend = $pos_of_value_above_threshold;
							print BED "$last_chrom\t$mypeakstarts[0]\t$tempend\t$peakid\t$peakval\n";
							$peakid++;
						}
					}
					else
					{
						print LOG "nopeak: $#mypeakstarts+1 < $minrun\n";
					}
					print LOG "starting new peak $chrom $start $value $endpoint\n";
					@mypeakstarts = @mypeakends = @mypeakvals = ();
					$build = 1;
					$endpoint = $end + $maxgap;
					push(@mypeakstarts,$start);
					push(@mypeakends,$end);
					push(@mypeakvals,$value);
					$pos_of_value_above_threshold = $end;
				}
			}
			elsif($build == 1 and $value <= $threshold)
			{
				if($start < $endpoint)
				{
					#keep going, add to peak, don't extend.
					print LOG "adding to peak not extending $chrom $start $value\n";
					push(@mypeakstarts,$start);
					push(@mypeakends,$end);
					push(@mypeakvals,$value);
					print LOG "_";
				}
				if($start >= $endpoint)
				{
					#finish peak, don't start a new peak.
					if($#mypeakstarts+1 >= $minrun)
					{
						print LOG "finishing peak $last_chrom $mypeakstarts[0] $mypeakends[$#mypeakends] $peakval\n";
						$peakval = median(@mypeakvals) * 1000;
						if($peakval > $overallthresh)
						{
							$tempend = $pos_of_value_above_threshold;
							print BED "$last_chrom\t$mypeakstarts[0]\t$tempend\t$peakid\t$peakval\n";
							$peakid++;
						}
					}
					else
					{
						print LOG "nopeak: $#mypeakstarts+1 < $minrun\n";
					}
					@mypeakstarts = @mypeakends = @mypeakvals = ();
					$build = 0;
				}
			}
			else
			{
				print LOG "here1\n";
			}
		}
		else #new chromosome.
		{
			if($build == 1 and $value > $threshold)
			{
				#finish peak and start a new peak
				if($#mypeakstarts+1 >= $minrun)
				{
					$peakval = median(@mypeakvals) * 1000;
					if($peakval > $overallthresh)
					{
						$tempend = $pos_of_value_above_threshold;
						print BED "$last_chrom\t$mypeakstarts[0]\t$tempend\t$peakid\t$peakval\n";
						$peakid++;
					}
				}
				else
				{
					print LOG "nopeak $#mypeakstarts+1 < $minrun\n";
				}
				@mypeakstarts = @mypeakends = @mypeakvals = ();
				$build = 0;
				$endpoint = $end + $maxgap;
				push(@mypeakstarts,$start);
				push(@mypeakends,$end);
				push(@mypeakvals,$value);
				$pos_of_value_above_threshold = $end;
			}
			elsif($build == 1 and $value <= $threshold)
			{
				#finish peak, don't start a new peak.
				if($#mypeakstarts+1 >= $minrun)
				{
					$peakval = median(@mypeakvals) * 1000;
					if($peakval > $overallthresh)
					{
						$tempend = $pos_of_value_above_threshold;
						print BED "$last_chrom\t$mypeakstarts[0]\t$tempend\t$peakid\t$peakval\n";
						$peakid++;
					}
				}
				else
				{
					print LOG "nopeak $#mypeakstarts+1 < $minrun\n";
				}
				@mypeakstarts = @mypeakends = @mypeakvals = ();
				$build = 0;
			}
			elsif($build == 0 and $value > $threshold)
			{	
				#start a peak... keep building until you can't find any more within maxgap.
				print LOG "starting a peak $chrom $start $end $value $endpoint\n";
				$endpoint = $end + $maxgap;
				push(@mypeakstarts,$start);
				push(@mypeakends,$end);
				push(@mypeakvals,$value);
				$pos_of_value_above_threshold = $end;
				$build = 1;
			}
			elsif($build == 0 and $value <= $threshold)
			{
				print LOG "x";
				#keep going, do nothing.
			}
			else
			{
				print LOG "else\n";
			}
		}
		$last_chrom = $chrom
	}
}

sub median
{
        my @distances = @_;
        if($#distances == 0)
        {
                return 0;
        }
        else
        {
                my (@rev_sorted,@sorted,$length,$med);
                @sorted = sort {$a <=> $b} @distances;
                @rev_sorted = sort {$b <=> $a} @distances;
                foreach my $item (@sorted)
                {
                }
                foreach my $item (@rev_sorted)
                {
                }
                $length = $#distances;
                $med = $sorted[$length/2];
                return $med;
        }
}

