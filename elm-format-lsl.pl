#!/bin/perl

=pod
Todo:
OK, current problem I've got to figure out how to solve.

1: the tokenizer relies on identifying static string tokens.

2: How to match against those when comment, such as /*-*/? Cannot rely
on whitespace deliniation there.

3: Probably (conditionally) "token matches last characters in running token string".

Just gotta figure out how to that. :O
=cut



use strict;
use warnings;
use Data::Dumper;
use constant { TRUE => 1, FALSE => 0 };
use constant { VERSION => "0.0.1" };
my $modeRunner = 0;
use constant
{ STAGE_PRE_STATE => $modeRunner++ #0
, STAGE_DEFAULT_ROOT => $modeRunner++ #1
, STAGE_STATE_ROOT => $modeRunner++ #2
, STAGE_POST_STATE => $modeRunner++ #3
, STAGE_EVENT => $modeRunner++ #4
, STAGE_USER_FUNCTION => $modeRunner++ #5
, STAGE_COMMENT_NONE => $modeRunner++ #6
, STAGE_COMMENT_TO_EOL => $modeRunner++ #7
, STAGE_COMMENT_TO_MARK => $modeRunner++ #8

, STAGE_MASK_ALL => 1<<$modeRunner - 1
};

use Getopt::Long;
Getopt::Long::Configure ("bundling");

my $getopt =
{ help => FALSE
, output => "" #blank means "unspecified", EG "overwrite input files".
, yes => FALSE
, validate => FALSE
, stdin => FALSE
, tabsize => 4
};

my $stageStack;
my $tokenAtoms =
{ '//' =>
  [ { valid => stageMask(STAGE_COMMENT_NONE)
    , action => sub { $stageStack->{'commented'} = STAGE_COMMENT_TO_EOL; }
    }
  ]
, '/*' =>
  [ { valid => stageMask(STAGE_COMMENT_NONE)
    , action => sub { $stageStack->{'commented'} = STAGE_COMMENT_TO_MARK; }
    }
  ]
, '*/' =>
  [ { valid => stageMask(STAGE_COMMENT_TO_MARK)
    , action => sub { $stageStack->{'commented'} = STAGE_COMMENT_NONE; }
    }
  ]
, "\n" =>
  [ { valid => stageMask(STAGE_COMMENT_TO_EOL)
    , action => sub { $stageStack->{'commented'} = STAGE_COMMENT_NONE; }
    }
  ]
}
;

GetOptions
( $getopt
, "help|h"
, "output:s"
, "yes"
, "validate"
, "stdin"
, "tabsize:4"
);

usage() if($getopt->{'help'});

my @targets;
while(my $target = shift @ARGV)
{ $target = escapeshellarg($target);
  if(defined(-d $target) && -d $target)
  { $target .= "/*.lsl"
  }
#  print Dumper("glob $target = ", glob $target);
  push @targets, glob $target;
}

usage() if(!@targets);

my $exitStatus = 0;
while(my $target = shift @targets)
{ if(!defined(-e $target) || !-e $target)
  { print "Input file doesn't exist: $target\n";
    $exitStatus = 1;
    next;
  }
  process($target);
}

sub process
{ my $target = shift;
  my $input;
  my $openStatus = open($input, "<", $target);
  if(!$openStatus)
  { print "Could not read file $target: @!\n";
    $exitStatus = 1;
    return;
  }
  $stageStack =
  { base => STAGE_PRE_STATE
  , token => ''
  , commented => STAGE_COMMENT_NONE
  , quoted => FALSE
  };
  while(my $line = <$input>)
  { my @chars = split '', $line;
    while(my $char = shift(@chars))
    { if($char =~ /[ \t]/)
      { tokenProcess();
        next;
      }
      $stageStack->{'token'} .= $char;
# print Dumper(tokenAtomsHash($stageStack));
      tokenProcess() if(tokenAtomsHash($stageStack)->{$stageStack->{'token'}});
      $stageStack->{'token'} = '' if($char=="\n");
    }
  }
  close($input);
}

sub tokenProcess
{ my $token = $stageStack->{'token'};
  $stageStack->{'token'} = '';
  return if(!$token);
  my $mask = stageMask($stageStack);
  if(my $scenes = $tokenAtoms->{$token})
  { foreach my $scene (@$scenes)
    { if($scene->{'valid'} & $mask)
      { $scene->{action}();
# print Dumper($stageStack) ."\n";
        $stageStack->{'token'} = '';
        return;
      }
    }
  }
# print $stageStack->{'commented'} ."($token):";
  return if($stageStack->{'commented'} ne STAGE_COMMENT_NONE);
  print
  ( "Found unexpected token: ($token) in mode/mask $mask\n"
  );
}

sub tokenAtomsHash
{ my $mask = stageMask(shift());
  my $tokenAtomsHash;
  foreach my $token (keys %$tokenAtoms)
  { foreach my $scene (@{$tokenAtoms->{$token}})
    { if($scene->{'valid'} & $mask)
      { $tokenAtomsHash->{$token}=1;
        last;
      }
    }
  }
  return $tokenAtomsHash;
}

sub stageMask
{ my $maskInput = shift;
  if(ref($maskInput) eq "HASH")
  { my $a = stageMask($maskInput->{'base'});
    my $b = stageMask($maskInput->{'commented'});
    # die("($a | $b == ". ($a|$b) .")");
    return($a|$b);
  } 
  return 1<<$maskInput;
}

sub escapeshellarg
{ my $arg = shift;

  $arg =~ s/'/'\\''/g;
  return "'" . $arg . "'";
}

sub usage
{ printf "elm-format-lsl.pl %s\n\n", VERSION;
  print <<~EOF;
    Usage: perl elm-format-lsl.pl [INPUT] [--output FILE] [--yes] [--validate] [--stdin]
      Format LSL source files in ELM-like fashion

    Available options:
      -h,--help     Show this help text
      --output FILE Write output to FILE instead of overwriting the given
                    source file.
      --yes         Reply 'yes' to all automated prompts.
      --validate    Check if files are formatted without changing them.
      --stdin       Read from stdin, output to stdout.
      --tabsize     How many spaces to tab (Default = 4)

    Examples:
      elm-format-lsl.pl Main.lsl                     # formats Main.lsl
      elm-format-lsl.pl Main.lsl --output Main2.lsl  # formats Main.lsl as Main2.lsl
      elm-format-lsl.pl src/                         # format all *.lsl files in the src directory

    Full guide to using elm-format-lsl.pl .. doesnt' yet exist.
    Because I'm lazy.
    Deal. ( •_•)>⌐■-■  (⌐■_■)
    EOF
  exit 1;
}

