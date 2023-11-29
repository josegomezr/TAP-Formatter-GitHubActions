TAP-Formatter-GitHubActions
===========================

Provide a Formatter for TAP::Harness that outputs Error messages for
[GitHub Actions (GHA)][0].

It's very alpha but does the best to grab out of the comments provided in the
TAP verbose output the file & line and any extra context to print in the
GHA annotations.

It converts TAP output like:
```
t/02-singleton.t .. 
# Subtest: Save
    not ok 1 - Init state

    #   Failed test 'Init state'
    #   at t/02-singleton.t line 14.
    # died: 1 at t/02-singleton.t line 14.
```

To:

```
::error file=t/02-singleton.t,line=14,title=Failed Tests::- Init state%0A--- CAPTURED CONTEXT ---%0A    # died: 1 at t/02-singleton.t line 14.%0A---  END OF CONTEXT  ---
::error file=t/02-singleton.t,line=25,title=Failed Tests::- Save
```

And those annotations render in PR's like so:
![github error annotation](./images/github-error-annotation.png)

INSTALLATION
------------
To install this module type the following:

```bash
perl Makefile.PL
make
make test
make install
```

DEPENDENCIES
------------
This module requires these other modules and libraries:

  - `TAP::Harness`

COPYRIGHT AND LICENCE
---------------------
Put the correct copyright and licence information here.

Copyright (C) 2023 by Jose D. Gómez R.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.38.0 or,
at your option, any later version of Perl 5 you may have available.


[0]: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#setting-an-error-message
