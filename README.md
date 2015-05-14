# vars.pl
A more powerful variables interface for Irssi.

Introduction
============
vars.pl was written to be able to insert any number of arguments into arbitrary locations within the input, replacing aliases and the elaborate rules required to achieve the same.

Full documentation can be found in the wiki. If the script is loaded and working, `/help vars` will print help.

Get started
===========
* Download the [latest stable version](https://github.com/ODyckhoff/vars.pl/archive/master.zip) of the script.
* Unzip the `master.zip` file and copy/move `vars.pl` from inside the `vars.pl-master` directory to your `.irssi/scripts/` or `.irssi/scripts/autorun/` directory:
```
  $ unzip master.zip
  $ mv vars.pl-master/vars.pl ~/.irssi/scripts/.
```
* Inside irssi, load the script:
```
  /script load vars.pl
```
* Done!

Basic usage
------------

Variables are simply inserted into text using a pair of curly braces around the variable name, for example, `{{pi}}`. If you had the variable `pi` saved with the value `3.141592654`, you could type into irssi:
```
    If you divide the circumference of a circle by its diameter, you get {{pi}}
```
It would be expanded and sent to the server as:
```
    If you divide the circumference of a circle by its diameter, you get 3.141592654
```

More advanced usage
-------------------
Variable values can contain references to variables themselves. Suppose you have several variables; `email`, which contains your email address, `phone`, which contains your telephone number, `address`, which contains your address, and so on.
You could create a further variable, `businesscard`, with the value: `Mrs. A. Person. Email: {{email}}, Tel No: {{phone}}, Address: {{address}}.`

The nested variables are expanded every time the `businesscard` variable is expanded. This means that if your email, telephone number, or address change, you can simply update those variables individually, and those changes will be reflected in the expansion of `businesscard`.

You can use these variables pretty much anywhere in the input buffer. If you have a comma separated list of IRC channels that you prefer in `mychans`, you could use: `/join {{mychans}}`

Outside usage
-------------
It's not officially supported, but unofficially, if you are a developer writing an irssi script that modifies the input buffer, you can use `{{name}}` notation and the variables will be expanded.
The same goes for anything that has a `command` subroutine, e.g. `Irssi::command()`, `Irssi::Server::Command()`, `Irssi::Window::Command()`, etc.
Using the above channels example, it's perfectly valid to write `Irssi::command('/join {{mychans}}');`

If you *don't* want vars.pl to do anything, append a `^` character after the `/`, e.g. `/^alias greeting say Good {{timeofday}}, everybody!`. In this instance, the braces are preserved because vars.pl was instructed not to act. This means that the `timeofday` variable can be updated, and the output of `/greeting` will change accordingly.

Plugins
=======
By far the biggest difference between version 1 and version 2 of `vars.pl`. Plugins dramatically increase the flexibility of this script by allowing the input to be modified in many ways.

A plugin to convert your text into Morse Code? How about a plugin to make all your text uppercase, or backwards?
Maybe even a plugin that analyses the text and returns a set of stats?

As simple or complex as you like, it can be done. Plugins are invoked via a prefix character nestled between the first and second opening curly braces. For example, if a Reverse plugin is loaded and set to use the `~` prefix character, you could use `{~{myvar}}`, and if the contents of `myvar` are `txet sdrawkcab`, then the output of the prefix invocation would be `backwards text`.

What really sets the plugins system apart is that it can operate also on non-variable text. Using an uppercasing plugin, I could write `{^{my caps lock doesn't work and I'm too lazy to hold shift, so I used this lousy plugin}}`.
This would be duly converted to: `MY CAPS LOCK DOESN'T WORK AND I'M TOO LAZY TO HOLD SHIFT, SO I USED THIS LOUSY PLUGIN`.

Using Plugins
-------------
*This is not the documentation on writing plugins. That's somewhere else*

* Put the file of the form `Name.pm` into the directory `~/.irssi/scripts/.varspl/Plugins/`
* In irssi, ensuring vars.pl is loaded, type `/vars load Name`, substituting `Name` accordingly. (Do not type the `.pm`).
* Invoke the plugin in text by using `{P{whatever}}`, replacing `P` with the appropriate prefix, and `whatever` with the relevant variable name, or text.

Again, full documentation can be found in the wiki.
