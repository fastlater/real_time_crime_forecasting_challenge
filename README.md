National Institute of Justice's Real-Time Crime Forecasting Challenge
=====================================================================
[NIJ RTCFC](https://www.nij.gov/funding/Pages/fy16-crime-forecasting-challenge.aspx)

$1.2 million dollars, of which I received $11,111.11.  According to me, they scored it incorrectly; a review of their BASIC macros suggests that they're using ArcGIS functions.  I do not have a license for that software, and as such, am unable to verify that their provided scoring script results in the numbers they posted.

These are simple Ruby scripts to score the submissions; I don't care enough to make sure they work in anybody else's environment, and I wrote them as a quick-and-dirty means to an end, but here they are.  Note that I am not an employee of the Department of Justice, and you should draw your own conclusions.  All information contained herein is based on my own program, which makes use of [shapelib](http://shapelib.maptools.org/), an open source C library for ArcGIS format files.


Why is this here?
=================
What can I say: I hate to appear spiteful, but they handled it very poorly and feeling like a victim sucks.

I firmly believe the National Institute of Justice owes me $50,000 to $100,000 dollars.  Suing them for it is problematic, as government attorneys are among the best in the country and I don't have $20,000.00 to try (my own legal skills aren't even at a third year law school level, and I'm too busy making a living to handle it myself.)  In short, I take issue with anybody who is unwilling to correct their mistakes or explain how and why they aren't mistakes.  As for criminality, my take is simple: since they designed the contest and have full legal authority to sponsor what they please within their legal budget (we're talking about a federal agency here), it's not technically a criminal misallocation of taxpayer dollars.

So they get away with not paying me, at the expense of my sticking a fully open source, reviewable contradiction of their numbers up somewhere.


Dependencies
============
- The directory structure.
- The NIJ files.
- Ruby's shapelib gem.
