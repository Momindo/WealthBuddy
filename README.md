# Wealth Buddy

Plan a big purchase: a car, a home, a vacation, a wedding. Answer a few questions and get a plan that says whether you can afford it, by when, and what to do first.

No account and no personal details. Everything stays on the phone, AES-256-GCM encrypted, with the key in the iOS Keychain or Android Keystore.

## How it works

1. **Pick a project:** car, home, build a house, vacation, wedding, education, home renovation, Hajj or Umrah, start a business, new baby, buy gold, phone or laptop, or something else.
2. **Answer the project questions:** cost, when you want it, and for a car, home, renovation or other purchase, savings or a loan (with down payment, rate and term). Rates have quick picks, including a 0% dealer offer for cars, and car loans go up to 5 years. Homes also ask your current rent.
3. **Answer the money questions:** take-home pay, monthly spending, savings, loan repayments, credit card balance, who relies on your income and how steady it is, and optional investments. These are asked once and reused for every project.
4. **Money set aside:** a new project asks whether you've already put money aside for it. Later, **Add money** on any project records a bonus, gift or sale, with a preview of how much sooner it makes the project before you confirm. The money can go to:
   - **The project:** held in its pot.
   - **Your safety cushion:** added to savings.
   - **Your credit card:** pays down the balance; anything beyond it goes to the project.

   If your cushion is short, the sheet shows when putting the money there reaches the same ready date and protects you sooner.
5. **Get the plan:**
   - a verdict: Ready now, On track, Later or Rethink
   - the numbers behind it
   - the steps in order, with dates
   - ways to make it work if it doesn't
   - things to watch out for

### The rules behind the plan (`lib/domain/assess.dart`)

1. **Credit card debt first.** Savings above one month of essentials pay it down now, then spare money each month clears the rest. Card interest is modelled at 3% a month.
2. **Safety cushion next.** Its size depends on your situation:

   | Your situation | Cushion |
   |---|---|
   | Only you rely on your income, fixed salary | 3 months of essentials |
   | Family relies on your income | 6 months |
   | Income varies | 3 months more on top |

   **Small purchases skip this step.** A purchase counts as small when it costs up to one month of take-home pay and is paid from savings. Your savings are still left alone, and the cushion comes after.
3. **Save the upfront amount.** That's the full price, or the down payment plus fees. Money set aside for the project counts first, then savings above the cushion. Set-aside money never skips steps 1 and 2: the plan still says to wait until the card is clear and the cushion is full.
4. **Buy, then check it still fits:**
   - Loan repayments must stay under the UAE's 50% cap; under 35% counts as comfortable.
   - Monthly costs afterwards must fit your spare money. Car running costs are estimated; a home adds upkeep and subtracts the rent you stop paying.

### Several projects at once (`lib/domain/plan.dart`)

Every project is planned together with the others by default. Spare money is split in **turns**:

```
Spare AED 8,000 a month                       Oct'26 ─ Feb'27 ─────── Sep'27 ──── Jun'28 ─────────────── Jun'31
Safety cushion first                          ████████
Turn 1 · saving now   Vacation  ~1,250/mo             ███████████████ ✓ on time
                      SUV       ~6,180/mo             ██████████████████████████ ✓ early
Turn 2 · waiting      Home      starts after both                                ███████████████████████ ✓ on time
                                (6,800/mo once the SUV's 1,200 running costs start)
```

1. The credit card, then the safety cushion, come first. Small purchases still save their monthly need during the cushion.
2. Each project's **need** is what's left to save ÷ months left to its date.
3. A turn is the largest group, nearest date first, whose needs fit in spare money and who all make their dates. Each gets its need; leftover goes to the nearest date.
4. Projects that don't fit **wait**; the next turn starts once everyone in this one has saved enough. Waiting is usually free: it still makes its date (the plan screen says so, or says by how much it slips).
5. Each project is bought on its date (or when ready, if late). From then on its loan, running costs, minus any rent it stops, change spare money and the cushion target for everyone after it.

Equal or proportional splits are avoided on purpose: when there isn't enough for everyone, they make everyone late at once.

On the plan screen, **How your spare money is split** shows who's saving now and how much, who waits and why ("Saving for all of them at once needs AED 11,980 a month. You have 8,000"). Two choices:
- **Save for this now too** pins a waiting project into the first turn, after previewing which dates move.
- **Plan this on its own** takes it out (with a warning that the others count on the same money).

Home cards say *Saving now · AED 6,180 a month* or *Waiting · starts Jun 2028*. Payday reminders split the money: "Put AED 1,250 for the vacation and AED 6,180 for the Family SUV today."

### Cost of waiting and the regret check

- **Cost of waiting** (when the verdict is *Later*): the delay is costed line by line in the verdict card. A home counts the rent you keep paying, minus the interest and upkeep you'd pay as an owner, plus the price rising. Trips, weddings, Hajj and education count price rises. A car's running costs make waiting a saving. "Find AED 1,200 more a month" says when that's less than what each month of waiting costs.
- **Regret check** (when the verdict is *Ready now* or *On track*), looking at the month after buying:

  | Check | Passes when |
  |---|---|
  | Cushion still covers you | it covers its months (less half a month) at the new monthly costs |
  | Room to breathe | at least 10% of pay is still spare |
  | Loans comfortable | repayments at or under 35% of pay |
  | Other plans hold | projects planned with it, no earlier than it, keep their dates |

  Two or more warnings make the verdict **Yes, but tight**, with a price that passes every check and a bigger down payment if one helps. One warning keeps the verdict and shows that line under it.

### What if (`lib/domain/whatif.dart`, `lib/ui/whatif_screen.dart`)

**What if…** (on home next to *Your projects*, and on every plan) opens sliders for take-home pay and monthly spending (±30%) and a want-by stepper per project. Every project's ready date, verdict and saving-now/waiting status update on each slider stop; the shared plan is re-run as a whole, so moving one date can move the others.

It also searches for the **smallest change that puts everything on time**: a spending cut or a pay rise, in AED 50 steps. Spending cuts count for more, because they also shrink the cushion needed first (late home example: 2,750 less spending does what 3,050 more pay does). **Try it** sets the slider. Nothing is saved until **Keep these changes**, which lists what will change first.

### What it costs the others (`lib/domain/impact.dart`)

Adding a project, or changing one's cost, date or loan, ends with a last step **only when other projects move**:
- each other project's ready date before → after, how far it moved, ⚠ when it now misses its want-by date, and verdict changes
- one sentence on why ("Spare money is AED 8,000 a month. Until Mar 2028 the Wedding needs about 6,150 of it, so the Family SUV has to wait.")
- the **earliest want-by date that keeps everything else on time** (galloping then binary search, up to 10 years), with **Use [date]**
- **Add it** / **Save changes** never blocks; it just puts the facts first

### Price staleness check

The app never goes online, so it remembers **when each price was last set or confirmed** (`Project.priceDate`) and asks again once prices of that kind usually move:

| Project | Ask again after |
|---|---|
| Car, home, build, renovation, wedding, business, baby, other | 6 months |
| Vacation, Hajj, phone or laptop | 3 months |
| Education | 12 months |
| Gold | only before buying (it moves daily; the amount is a budget) |
| Any loan rate | 3 months |

Within 2 months of buying it always asks for a fresh quote (if the price is more than 2 weeks old). The home card shows "⏱ Price checked 7 months ago"; the plan shows **Is AED 120,000 still right?** with **Still right** (re-dates it) or **Update**, which previews the new ready date and what it does to the other projects before **Save price**. Projects saved before 0.8.0 start from the day of the update.

### Plan history (`lib/domain/history.dart`)

Each project keeps the ready month its plan gave over time, with the reason it moved. A point is added only when the month changes:
- changes you make carry their reason: "Added AED 25,000 (bonus)", "Wedding added", "Family SUV: price updated to AED 128,000", "What-if changes kept", "Money answers updated"
- a move found just before a change, or when the app opens, with nothing new entered, is recorded as **"Time passed with the same answers"**, so a slip isn't blamed on the wrong thing

The plan screen shows **How your date has moved**: "3 months sooner since you started" (or later, with the biggest step back named), a step chart (higher is sooner, dashed line = want-by) and every change. Home cards show the same one-liner. Up to 60 points per project; the first is always kept.

### Check-in and drift (`lib/domain/checkin.dart`)

The phone can't see the bank, so plans **assume you follow them**. Savings and card answers are dated (`Money.asOf`); every plan starts from what you'd have today if you had followed it since then (`projectedToday`), so ready dates no longer slip just because a month passes. Assumed saving shows on the plan as "Planned saving since Oct 2026 · assumed until you check in".

A **monthly check-in** keeps that honest. It's due when the answers are a month old and there hasn't been one in 25 days (home banner, or Settings → Check in now):
1. "If you followed the plan since Oct 2026, you'd have about AED 21,000." Enter what you have now (or **About right**), and the card balance if there is one.
2. The plan restarts from the real numbers; history records "Check-in: AED 3,000 behind plan".
3. When the gap per month is more than AED 250 or 10% of spare money, it suggests the spending that would explain it: "If that's regular, your spending is closer to AED 13,500 than 12,000." **Update spending** or **It was a one-off**.

### Why not yet

Every plan that isn't ready now gets one sentence naming the blocker, on the verdict card and the home card, in this order: waiting on an unreachable project, nothing spare, loan over the cap, costs after buying too high, more than 30 years away, the credit card first, waiting for other projects, the safety cushion first, otherwise progress ("You're 53% of the way: AED 56,000 to go at AED 8,000 a month").

### Screens (0.11–0.12)

- **Home**: once you have projects, the type grid moves behind **+ New project**. A **This payday** card at the top says the one thing to do with this month's money across all projects (from the payday reminder logic), with **Done ✓** on payday and **Check in** when due. Each project card has a single status line, by priority: stale price → why not yet → how far the date has moved. **Timeline** shows every project on one line of time (see Timeline below).
- **Plan screen**: a summary (progress ring, verdict, headline, why not yet, cost of waiting, regret check), then three tabs: **Plan** (steps, ways to make it work, What if, Change answers), **Money** (set aside, how spare money is split, the numbers), **More** (history, good to know).
- **First run**: privacy pop-up, then a 4-card **feature tour** with parallel projects as the showcase (replay from Settings → How it works). Money questions are 3 screens (your pay; your month; debts and situation). "When do you want it?" has quick choices plus a month-and-year picker. Amounts show thousands separators as you type, and 120k / 1.2m work.
- **Polish**: delete and "plan on its own" happen straight away with **Undo** instead of an "are you sure?"; a one-time celebration with confetti when a project becomes affordable; haptic ticks on what-if sliders; screen-reader labels for progress, the history chart and the timeline.

### Big number, no-cushion option, motion (0.13)

- **The big number** (home, top): the smallest amount to put aside each month so every project makes its date — found by re-running the whole shared plan at different spare amounts (`neededMonthly`, AED 10 steps), so it counts the card, the cushion and the costs each purchase adds. Below it: "You have AED 8,000 spare · ✓ 570 to spare" or "⚠ 930 short" (opens What if…). Cached per data change.
- **Plan without a safety cushion**: Settings → Planning → "Keep a safety cushion first" (on by default), also a switch in What if…. Off means the cushion target is 0: savings go to projects straight away, the cushion step and its regret check disappear, the card still comes first. Turning it off previews which ready dates move; while off, home and every plan show a warning with "Turn back on".
- **Motion** (`lib/ui/motion.dart`, all 200–700 ms, none loop, off with the phone's reduce-motion setting): the big number and % ring count up; progress bars fill; project cards rise in one after another; verdict tags and headlines cross-fade; plan tabs fade; Android screens fade-and-rise (iOS keeps swipe-back); the payday card's Done draws a tick then folds away; timeline bars grow; cards press down slightly.

### Timeline (0.14)

Every project on one horizontal timeline, years across the top and one lane per project: a thin grey line while it waits (or the card and cushion come first), a green bar while it saves, an amber tick for the date you want it, and a ✓ pin on the buy date ("Jul 2028 · on time"). A purple playhead with the year sweeps once from today to the last goal, the bars growing behind it, and sweeps again whenever the plan changes. A compact version sits on home whenever you have projects; tap it (See details) for the full view, where tapping a lane opens that plan. Reduce motion shows the end state.

## App basics

- **Logo:** steps rising to a gold coin. `lib/ui/logo.dart` draws it as a vector for the app bar and splash, and `tool/make_brand.py` renders the same geometry to the app icon, Android adaptive icon, notification icon and native splash PNGs in `assets/brand/`.
- **First launch:** a three-second splash, then a one-time privacy pop-up and the feature tour: everything stays on this phone, encrypted; no cloud and no account; no ads and no tracking; no name, email or phone number. It's available again from Settings → Privacy.
- **Payday reminders:** the money questions include the day salary arrives. At 3 pm on payday a local notification says what to do with this month's spare money, written from the plan by `lib/domain/reminders.dart`:
  - pay down the card
  - fill the safety cushion
  - put aside X for the project, with the percentage reached
  - or "You can afford the …" once it's ready

  The next three are scheduled on the phone and refreshed on every change. The phone can't see the bank, so messages say what to do rather than claiming anything was saved.
- **Settings:** appearance (system, light or dark), payday reminder on or off and the payday itself, app lock with fingerprint, face or phone PIN, update my money, privacy, delete all data, version.

## Run it

```bash
./tool/setup.sh     # generates Android and iOS folders, applies tool/patch_platforms.py, makes icons and splash
flutter test        # engine scenarios + smoke test
flutter run
```

CI (`.github/workflows/ci.yml`) runs analyze, tests, an Android debug APK and an unsigned iOS build on every push. It publishes the full output to the `ci-reports` branch.

## Layout

```
lib/
  domain/
    assess.dart      Project kinds, which questions to ask, the decision engine
    models.dart      Money (asked once) and Project
    format.dart      AED formatting and month helpers
  data/encrypted_store.dart
  app/state.dart     Riverpod controller, saves on every change
  ui/
    home_screen.dart    Pick a project, your projects
    wizard_screen.dart  One question per screen
    result_screen.dart  Verdict, numbers, plan, options
test/
  assess_test.dart   Scenarios: no cushion, small purchase, card debt, loan over cap,
                     overspending, ready now, home rent offset, too soon
  widget_test.dart
```

## Numbers to verify before release

| Assumption | Value used |
|---|---|
| Lending | 50% repayment cap; 20% minimum down for cars and expat mortgages; car loans usually up to 48 months, some banks 60; mortgage fees about 6% |
| Car running costs | 12% of the price a year |
| Home upkeep | 1.5% of the price a year |
| Card interest | 36% a year |
| Small-purchase threshold | One month of take-home pay |
| Price rises (cost of waiting) | Homes, building, renovation 3% a year; trips, weddings, Hajj 4%; education 5% |
| Price holds for | 3, 6 or 12 months by type; loan rates 3 months; fresh quote within 2 months of buying |
| Regret check | Spare after buying ≥ 10% of pay; repayments ≤ 35%; cushion within half a month of its target |
