#!/bin/perl
use strict;
use warnings;
use Data::Dumper;
use open qw(:std :utf8);
use constant { TRUE => 1, FALSE => 0 };
use constant { VERSION => "0.0.1" };

=pod
## Production notes

OK, now it's getting stuck in a loop someplace. Need to debug.
=cut

my($symbols, $inputLine, $symbolIndex);
my $indent = 0;
my $inputRow = 0;
my $inputColumn = 0;

my $lexemeTemplates =
{ CommentSingleLine => qr(\/\/)
, CommentMultiLineBegin => qr(\/\*)
, CommentMultiLineEnd => qr(\*\/)
, Newline => qr([\r\n]+)
, Whitespace => qr(\s+)
, BlockBegin => qr(\{)
, BlockEnd => qr(\})
, ParenBegin => qr(\()
, ParenEnd => qr(\))
, BracketBegin => qr(\[)
, BracketEnd => qr(\])
, StatementEnd => qr(\;)
, Comma => qr(,)
, DoubleQuote => qr(")
, Name => qr([a-zA-Z_][a-zA-Z_0-9]*)
, UnaryOperators => qr(-|!|~)
, IncrementDecrement => qr(--|\+\+)
, Assignment => qr([+*/%-]?=)
, BinaryOperators => # Assignment not included
  qr
  ( [+*/%-] # Arithmetic
  | == #Comparison
  | !=
  | [<>]=?
  | \|\|? #Bitwise and Logical
  | &&?
  | \^
  | \<\<
  | >>
  )x
, Type => qr(integer|string|list|vector|rotation)
};

# Set Lexeme Keywords
( sub
  { while(my $keyword = shift)
    { $lexemeTemplates->{ucfirst($keyword)} = qr($keyword);
    }
  }
)->(qw(return if while do else for jump));

$lexemeTemplates =
{ %$lexemeTemplates
, ( StateDeclaration => LexemeTemplate('default | state Name')
  , TypeCast => LexemeTemplate('ParenBegin Type ParenEnd')
  )
};

# Lexemes will be checked in order, beginning with this list in this order.
# So first item here will be first lexeme checked.
my $lexemePreList =
[ qw( Type
      Whitespace
  )
];

# Lexemes will be checked in order, ENDING with this list in this order.
# So LAST item here will be last lexeme checked.
my $lexemePostList =
[ qw( Name
  )
];

# Thus, this becomes the final ordering of all lexemes.
my $lexemeOrderHash = {};

#custom scope limiter
{
  my $index = 0;

  foreach my $template (@$lexemePreList, keys %$lexemeTemplates)
  { if(!defined $lexemeOrderHash->{$template})
    {
      $lexemeOrderHash->{$template} = $index++;
    }
  }
  foreach my $template (@$lexemePostList)
  { # Not skipping items already accounted for.
    # Warning: this will swiss cheese the list a little bit,
    # so your algos need to be tolerant of a swiss-cheese
    # ordering.
    $lexemeOrderHash->{$template} = $index++;
  }
}

my $lexemeOrder = 
[ sort
    {$lexemeOrderHash->{$a} <=> $lexemeOrderHash->{$b}}
    keys %$lexemeOrderHash
];

sub LexemeTemplate
{ my $template = shift;
  $template =~
    s/(^| )([A-Z][a-zA-Z]+)/
      ($2 eq 'Whitespace')
      ?($lexemeTemplates->{Whitespace})
      :($lexemeTemplates->{$2} .'?'. $lexemeTemplates->{$2})
    /eg;
#print "!$template!\n";
  qr($template)x;
}

sub ParseProgram
{ $symbolIndex = 0; # Forget lookahead
  IgnoreWhitespace();
  while(!ParseAccept('State'))
  { if(ParseAccept('Type'))
    { IgnoreWhitespace();
      if(ParseAccept('ParenBegin'))
      { ParseFunction();
      } else
      { ParseVariableDeclaration();
        ParseStatementEnd();
      }
    } else
    { ParseExpect('Name', "Program header, user function returning void");
      ParseFunction();
    }
    IgnoreWhitespace();
  }
  IgnoreWhitespace();
  while(!ParseAccept('EOF'))
  { ParseState();
  }
  IgnoreWhitespace();
die("DONE");
}

sub ParseExpression
{ $symbolIndex = 0; # Forget lookahead
  ParseExpect('Expression', "TODO expression"); # TODO
}

sub ParseStatementEnd
{ $symbolIndex = 0; # Forget lookahead
  ParseExpect('StatementEnd', "End of a statement");
  WriteSymbol(''); # Just statement end
  WriteSymbol("\n"); # Just newline
}

sub ParseVariableDeclaration
{ $symbolIndex = 0; # Forget lookahead
  ParseExpect('Type', "Variable Declaration");
  WriteSymbol(RenderIndent()); # indent + type
  IgnoreWhitespace();
  ParseExpect('Name', "Variable Declaration");
  WriteSymbol(' '); # space + name
  IgnoreWhitespace();
  ParseExpect('Assignment', "Variable Declaration");
  WriteSymbol(' '); # space + assignment operator
  IgnoreWhitespace();
  WriteSymbol("\n"); # Just newline
  ++$indent;
  WriteSymbol(RenderIndent()); # Just new indent
  ParseExpression(); # Consume expression
  --$indent;
  return; # caller must end statement for us
}

sub ParseStatement
{ $symbolIndex = 0; # Forget lookahead
  if(ParseAccept('Type'))
  { ParseVariableDeclaration();
    return;
  }
  if(ParseAccept('Return'))
  { WriteSymbol(RenderIndent()); # indent + return
    IgnoreWhitespace();
    if(ParseAccept('StatementEnd'))
    { $symbolIndex = 0; # Forget lookahead
      return; # caller must end statement for us
    }
    ParseExpect('ParenBegin', "Return statement parenthesized value");
    WriteSymbol(''); # Just (
    ParseExpression();
    ParseExpect('ParenEnd', "Return statement parenthesized value");
    return; # caller must end statement for us
  }
  ParseExpect('Statement', "TODO Statement"); # TODO
}

sub ParseFunction
{ $symbolIndex = 0; # Forget lookahead
  # NOTE: $indent may be 0 for user functions or 1 for events
  IgnoreWhitespace();
  if(ParseAccept('Type'))
  { WriteSymbol(RenderIndent()); # indent + type
    IgnoreWhitespace();
    WriteSymbol(' '); # just space
  } else
  { WriteSymbol(RenderIndent()); # Just indent
  }
  ParseExpect('Name', "Function");
  WriteSymbol(''); # Just name
  IgnoreWhitespace();
  ParseExpect('ParenBegin', "Function");
  WriteSymbol(''); # Just ParenBegin
  IgnoreWhitespace();
  while(!ParseAccept('ParenEnd'))
  { ParseExpect('Type', "Function argument");
    WriteSymbol(''); # Just type
    IgnoreWhitespace();
    ParseExpect('Name', "Function argument");
    WriteSymbol(' '); # space + name
    my $symbol = ParseExpect('Comma', 'ParenEnd', "more function arguments?");
    if($symbol->{template} eq 'Comma')
    { IgnoreWhitespace();
      WriteSymbol(''); # Just comma
      WriteSymbol(' '); # Just space
    } else
    { $symbolIndex--; # Roll back lookahead to re-test ParenEnd in while loop
    }
  }
  WriteSymbol(''); # Just ParenEnd
  IgnoreWhitespace();
  ParseExpect('BlockBegin', "Function block");
  WriteSymbol("\n" . RenderIndent()); # newline + indent + {
  $indent++;
  while(!ParseAccept('BlockEnd'))
  { ParseStatement();
    ParseStatementEnd();
  }
  $indent--;
  WriteSymbol("\n" . RenderIndent()); # newline + }
  WriteSymbol("\n\n"); # Blank line
}

sub ParseState
{ $symbolIndex = 0; # Forget lookahead
  # $indent must equal 0, so I'm never trying to render it here.
  ParseExpect('State', "New State");
}

sub RenderIndent
{ return("  " x $indent);
}

sub WriteSymbol
{ my $whitespace = shift;
  die("WriteSymbol called while \$symbolIndex = $symbolIndex, instead of 0 or 1 as required.")
    unless($symbolIndex<2);
  if(defined $symbols)
  { print $whitespace . $symbols->[0]{content};
    splice @$symbols, 0, $symbolIndex; # Discard topmost symbols up to and excluding $symbolIndex.
  }
  $symbolIndex = 0;
}

sub ReadSymbol
{ while(!defined($symbols->[$symbolIndex]))
  {
# print Dumper
# ( { label => "Before read"
#   , where => "($inputRow, $inputColumn)"
#   , remaining => $inputLine
#   , symbols => $symbols
#   , symbolIndex => $symbolIndex
#   }
# );

    if(!defined $inputLine || $inputLine eq '') # Blank at symbol read means end of line reached.
    { $inputRow++;
      $inputColumn = 0;
      $inputLine = <> || die "Reading from STDIN failed at line $inputRow: $!";
      return({ 'template' => 'EOF', symbolContent => '' })
        unless($inputLine); # Blank right after a file read means end of file reached.
    }
    for my $template (@$lexemeOrder)
    { if($inputLine =~ s/^(?<symbolContent>$lexemeTemplates->{$template})//)
      { my $symbol =
        { template => $template
        , content => $+{symbolContent}
        };
        push @$symbols, $symbol;
        $inputColumn += length $+{symbolContent};
        last;
      }
    }
# print Dumper
# ( { label => "After read"
#   , where => "($inputRow, $inputColumn)"
#   , remaining => $inputLine
#   , symbols => $symbols
#   , symbolIndex => $symbolIndex
#   }
# );
  }
# die;
  return $symbols->[$symbolIndex];
}

sub TestTemplates
{ my $testTemplates = shift;
  my $functionName = shift;
  my $lambda = shift;
  $testTemplates = [$testTemplates] if(ref($testTemplates) eq '');
  die("Bad test templates passed to $functionName: ". Dumper($testTemplates))
    unless(ref($testTemplates) eq 'ARRAY');
  foreach my $testTemplate (@$testTemplates)
  { my $ret = $lambda->($testTemplate);
    # Allow lambda to short circuit other checks by returning singleton array
    return($ret->[0]) if(ref($ret) eq 'ARRAY');
  }
  return(FALSE);
}


sub ParseAccept
{ my $testTemplates = shift;
  return TestTemplates
    ( $testTemplates
    , 'ParseAccept'
    , sub
      { my $symbol = ReadSymbol($testTemplates);
        my $template = shift;
        if($symbol->{template} eq $template )
        { $symbolIndex++;
          # die(Dumper($symbol));
          return([$symbol]);
        }
      }
    );
}

sub ParseExpect
{ my $testTemplates = shift;
  my $label = shift;
  my $found = TestTemplates
    ( $testTemplates
    , 'ParseExpect'
    , sub
      { my $symbol = ParseAccept(shift);
        if($symbol)
        { return [$symbol];
        }
      }
    )
    || FALSE
    ;

  if($found)
  { return($found);
  }
  my $symbol = ReadSymbol($testTemplates);
  die
  ( "Unexpected $symbol->{template} Symbol '$symbol->{content}' found at "
  . "input ($inputRow, $inputColumn) during \"$label\"."
  . " We were instead expecting one of: "
  . Dumper($testTemplates)
  ."\nRemaining line was $inputLine."
  );
}

sub ParseIgnore
{ $symbolIndex = $symbolIndex || 0;
  TestTemplates
  ( shift
  , 'ParseIgnore'
  , sub
    { my $testTemplate = shift;
      if(ParseAccept($testTemplate))
      { if($symbolIndex == 1)
        { shift @$symbols;
          $symbolIndex = 0;
        }
        return ParseIgnore($testTemplate);
      }
    }
  )
}

sub IgnoreWhitespace
{ ParseIgnore(['Whitespace']);
}

ParseProgram();
