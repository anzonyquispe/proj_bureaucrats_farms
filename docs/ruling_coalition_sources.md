# State ruling coalitions, outside support and pre-poll alliances: coding and sources

This file documents the coding in `code/_stacked_downup_replication/_ruling_coalition.do` (state governments) and the pre-poll alliances in `_mla_party.do`. They feed:
- the DISHA ruling-coalition shares (`_disha_fragmentation.do`);
- the Figure 3 decomposition by coalition (`_app_coalition_generation.do`).

The sources were checked in November 2026. Every claim below rests on a page that was opened, with its link.

## Rules

- **`coalition` (version 1, the government).** An MLA counts as 1 if:
  - their party has at least one minister in the state council of ministers that month, or
  - they are an independent who is a minister that month.
- **`coalition_ext` (version 2, government plus outside support).** It is `coalition` plus the parties and independent MLAs that backed the government without ministers.
  - Support must be documented: a letter of support to the Governor, a vote in a trust or no-confidence motion, or a public declaration.
  - It counts from the month of that support until it is documented as withdrawn, or until a new government (a new CM) needs fresh evidence.
  - Support that no source documents counts as 0.
- **Timing.** The month of a change belongs to the new status. This applies to new governments, ministers appointed or resigning, and support given or withdrawn.
- **Party.** An MLA's party is the one they won the general election with. By-elections and defections are not followed. The main cases left out are listed at the end.
- **Government level.** The state government, not the central one (team's answer, 11 Nov 2026).
- **Coverage.** April 2012 to January 2023.
  - The DISHA rural sample covers Bihar and Uttar Pradesh from 2012m12, Haryana from 2017m3 and Punjab from 2017m12, all to 2022m8.

## Governments

| Period | Dates | CM | Cabinet parties (`coalition`) | Outside support (`coalition_ext` only) |
|---|---|---|---|---|
| PB2012 | 14 Mar 2012 – 16 Mar 2017 | P.S. Badal | SAD, BJP | Bains brothers (IND), to Feb 2014 |
| PB2017 | 16 Mar 2017 – 16 Mar 2022 | Amarinder Singh; Channi from 20 Sep 2021 | INC | none |
| PB2022 | from 16 Mar 2022 | Bhagwant Mann | AAP | none |
| HR2009 | 25 Oct 2009 – 26 Oct 2014 | B.S. Hooda | INC; 4 independent ministers | BSP; all 7 independents |
| HR2014 | 26 Oct 2014 – 27 Oct 2019 | M.L. Khattar | BJP | BSP; 3 independents |
| HR2019 | from 27 Oct 2019 | M.L. Khattar | BJP, JJP; Ranjit Chautala (IND) from Nov 2019 | HLP; 6 independents (two withdrew) |
| UP2012 | 15 Mar 2012 – 19 Mar 2017 | Akhilesh Yadav | SP; Raja Bhaiya (IND) | none |
| UP2017a | 19 Mar 2017 – 20 May 2019 | Yogi Adityanath | BJP, Apna Dal (S), SBSP | NISHAD from Apr 2019; Aman Mani Tripathi (IND) |
| UP2017b | from 20 May 2019 (SBSP minister dismissed) | Yogi Adityanath | BJP, Apna Dal (S) | NISHAD; Aman Mani Tripathi (IND) |
| UP2022 | from 25 Mar 2022 | Yogi Adityanath | BJP, Apna Dal (S), NISHAD | Jansatta Dal (Loktantrik) |
| BR2010a | 26 Nov 2010 – 16 Jun 2013 | Nitish Kumar | JD(U), BJP | none (no evidence) |
| BR2010b | 16 Jun 2013 – 20 Nov 2015 (Manjhi CM 20 May 2014 – 20 Feb 2015) | Nitish; Manjhi; Nitish | JD(U); 2 independent ministers from May 2014 | INC, CPI; RJD from May 2014; 4 independents |
| BR2015a | 20 Nov 2015 – 26 Jul 2017 | Nitish Kumar | JD(U), RJD, INC | none |
| BR2015b | 27 Jul 2017 – 16 Nov 2020 | Nitish Kumar | JD(U), BJP; LJP until Apr 2019 | LJP; RLSP; HAM(S) until Jan 2018; 4 independents |
| BR2020a | 16 Nov 2020 – 9 Aug 2022 | Nitish Kumar | BJP, JD(U), HAM(S); VIP until Feb 2022; Sumit Kumar Singh (IND) from Feb 2021 | Sumit Kumar Singh until his appointment |
| BR2020b | from 10 Aug 2022 | Nitish Kumar | JD(U), RJD, INC, HAM(S); Sumit Kumar Singh (IND) | CPI(ML)L, CPI, CPI(M) |

### Sources for the governments

**Punjab**
- https://en.wikipedia.org/wiki/Fifth_Badal_ministry
- https://www.tribuneindia.com/2012/20120315/main2.htm
- https://en.wikipedia.org/wiki/Second_Amarinder_Singh_ministry
- https://en.wikipedia.org/wiki/Charanjit_Singh_Channi_ministry
- https://en.wikipedia.org/wiki/Bhagwant_Mann_ministry
- https://www.tribuneindia.com/news/punjab/mann-govt-wins-trust-vote-with-93-in-favour-437847

**Haryana**
- https://en.wikipedia.org/wiki/Second_Hooda_ministry
- https://www.tribuneindia.com/2009/20091108/main1.htm (trust vote, 28 Oct 2009)
- https://en.wikipedia.org/wiki/First_Khattar_ministry
- https://www.millenniumpost.in/bjp-gets-support-of-bsp-3-independents-42792
- https://www.tribuneindia.com/2014/20141022/haryana.htm
- https://en.wikipedia.org/wiki/Second_Khattar_ministry
- https://www.tribuneindia.com/news/archive/haryana/10-inducted-into-haryana-cabinet-860764
- https://www.dtnext.in/national/2021/03/10/cong-noconfidence-motion-against-bjpjjp-govt-in-haryana-defeated (no-confidence motion of 10 Mar 2021: 55 = 39 BJP + 10 JJP + 5 IND + 1 HLP)

**Uttar Pradesh**
- https://en.wikipedia.org/wiki/Akhilesh_Yadav_ministry
- https://en.wikipedia.org/wiki/First_Yogi_Adityanath_ministry
- https://www.indiatvnews.com/news/india-uttar-pradesh-governor-ram-naik-yogi-adityanath-request-to-dismiss-om-prakash-rajbhar-election-2019-521205 (SBSP minister dismissed, 20 May 2019)
- https://www.asianage.com/india/all-india/050419/gorakhpur-mp-joins-bjp-may-contest-from-east-up.html (NISHAD joins the NDA, Apr 2019)
- https://en.wikipedia.org/wiki/Second_Yogi_Adityanath_ministry
- https://www.patrika.com/lucknow-news/raghuraj-pratap-singh-raja-bhaiya-kunda-mla-said-i-am-in-government-7440976/ (JDL: "we are already in the government", 2022)

**Bihar**
- https://en.wikipedia.org/wiki/Third_Nitish_Kumar_ministry
- https://www.millenniumpost.in/nitish-calls-it-quits-29942 (BJP ministers dismissed, 16 Jun 2013)
- https://www.gulf-times.com/story/356700/nitish-is-confident-of-winning-trust-vote
- https://www.domain-b.com/economy/Govt/20130619_nitish_kumar.html (trust vote of 19 Jun 2013, 126–24: JD(U), INC, CPI and 4 independents)
- https://en.wikipedia.org/wiki/Jitan_Ram_Manjhi_ministry
- https://www.indiatvnews.com/news/india/chief-minister-jitan-ram-manjhi-wins-trust-vote-in-bihar-37169.html (trust vote of 23 May 2014: JD(U), RJD, INC, CPI)
- https://en.wikipedia.org/wiki/2015_Bihar_political_crisis
- https://en.wikipedia.org/wiki/Fourth_Nitish_Kumar_ministry
- https://www.millenniumpost.in/nitish-kumar-sails-through-bihar-trust-vote-57534 (trust vote of 11 Mar 2015)
- https://en.wikipedia.org/wiki/Fifth_Nitish_Kumar_ministry
- https://en.wikipedia.org/wiki/Sixth_Nitish_Kumar_ministry (LJP minister Jul 2017 – May 2019)
- https://www.indiatvnews.com/politics/national-nitish-govt-wins-confidence-vote-131-108-393698 (trust vote of 28 Jul 2017: JD(U), BJP, LJP, RLSP, HAM, 4 IND)
- https://www.deccanchronicle.com/nation/current-affairs/280218/former-bihar-cm-jitan-ram-manjhi-joins-rjd-led-grand-alliance.html (HAM leaves the NDA, 28 Feb 2018)
- https://www.outlookindia.com/national/setback-to-upender-kushwahas-rlsp-legislators-announce-to-remain-with-nda-news-321801
- https://en.wikipedia.org/wiki/Seventh_Nitish_Kumar_ministry
- https://scroll.in/latest/1020528/bihar-after-bjps-request-vip-chief-mukesh-sahani-sacked-by-cm-nitish-kumar (VIP minister sacked, 27 Mar 2022)
- https://en.wikipedia.org/wiki/Eighth_Nitish_Kumar_ministry
- https://www.orissapost.com/nitish-kumar-stakes-claim-to-form-government-again-after-resigning-as-nda-chief-minister (support list of 9 Aug 2022)
- https://www.freepressjournal.in/india/bihar-left-legislators-not-to-join-nitish-kumar-cabinet-will-extend-support-from-outside

## Independent MLAs

AC ids are `ac_uq_id`. "Minister" sets both versions to 1; "supported" sets only `coalition_ext` to 1. Everything else is 0.

### Punjab

| AC (id) | MLA | Term | Coding | Source | Confidence |
|---|---|---|---|---|---|
| Atam Nagar (398), Ludhiana South (406) | Simarjit and Balwinder Bains | 2012 | Supported to Feb 2014: SAD associate members, parted ways 5 Mar 2014 | https://www.tribuneindia.com/news/archive/comment/ludhiana-s-brothers-in-arms-291801 ; https://www.tribuneindia.com/2014/20140306/punjab.htm | Medium (end date low) |
| Mukerian (382) | Rajnish Kumar Babbi | 2012 | 0: no evidence | https://en.wikipedia.org/wiki/Rajnish_Kumar_(politician) | – |
| Sultanpur Lodhi (not in DISHA) | Rana Inder Partap Singh | 2022 | 0: opposition | https://en.wikipedia.org/wiki/Rana_Inder_Pratap_Singh | Medium |

### Haryana

| AC (id) | MLA | Term | Coding | Source | Confidence |
|---|---|---|---|---|---|
| Panipat Rural (309) | Om Prakash Jain | 2009 | Minister Nov 2009 – May 2011 (resigned 9 Jun 2011); 0 after | https://twocircles.net/?p=252810 | High |
| Sirsa (322) | Gopal Kanda | 2009 | Minister Nov 2009 – Jul 2012 (resigned 5 Aug 2012); 0 after | https://en.wikipedia.org/wiki/Gopal_Goyal_Kanda | High |
| Faridabad NIT (258) | Shiv Charan Lal Sharma | 2009 | Minister of State from Nov 2009 | https://en.wikipedia.org/wiki/Second_Hooda_ministry | High |
| Gurgaon (269) | Sukhbir Kataria | 2009 | Minister of State from Nov 2009 | https://en.wikipedia.org/wiki/Sukhbir_Kataria | High |
| Fatehabad (264), Hathin (259), Pundri (293) | Gillan Khera, Jaleb Khan, Sultan | 2009 | Supported: chief parliamentary secretaries | https://www.indiatvnews.com/news/india/hooda-rewards-all-7-independents-with-ministerial-berths-kiran-savitri-out-499.html | High |
| Samalkha (310), Punahana (272), Pundri (293) | Machhrouli, Rahish Khan, Kaushik | 2014 | Supported: letter of 21 Oct 2014 | https://www.millenniumpost.in/bjp-gets-support-of-bsp-3-independents-42792 | High |
| Kalayat (292) | Jai Parkash | 2014 | 0: opposition | https://www.theweek.in/news/india/2019/09/16/independent-mla-from-haryana-inld-leaders-join-congress.amp.html | Medium |
| Safidon (288) | Jasbir Deswal | 2014 | 0: no evidence | – | – |
| Rania (321) | Ranjit Singh Chautala | 2019 | Supported from Oct 2019; cabinet minister from 14 Nov 2019 | https://www.tribuneindia.com/news/archive/haryana/vij-allocated-home-gujjar-education-860977 | High |
| Badshahpur (267), Prithla (262), Nilokheri (298), Pundri (293) | Daulatabad, Rawat, Gonder, Gollen | 2019 | Supported through the window | https://www.outlookindia.com/national/support-of-the-six-of-seven-independents-to-khattar-govt-is-unconditional-haryana-min-ranjit-chautala-news-297536 | High |
| Meham (316) | Balraj Kundu | 2019 | Supported to Jan 2020; withdrew 27 Feb 2020 | https://www.tribuneindia.com/news/kundu-withdraws-support-no-threat-to-khattar-govt-48186 | High |
| Dadri (252) | Sombir Sangwan | 2019 | Supported to Nov 2020; withdrew 1 Dec 2020 (no return date found) | https://www.indiatvnews.com/news/india/sombir-sangwan-withdraws-support-khattar-government-haryana-independent-mla-668568 | High |

### Uttar Pradesh

| AC (id) | MLA | Term | Coding | Source | Confidence |
|---|---|---|---|---|---|
| Kunda (775) | Raghuraj Pratap Singh (Raja Bhaiya) | 2012 | Minister except Mar–Sep 2013 (resigned 4 Mar 2013, back 11 Oct 2013) | https://www.oneindia.com/2013/03/04/how-raja-bhaiya-boon-for-mayawati-bane-for-akhilesh-up-1163307.html ; https://www.millenniumpost.in/raja-bhaiya-back-as-minister-in-sp-govt-cong-targets-party-185336 | High |
| Duddhi (827) | Ruby Prasad | 2012 | 0: joined SP Apr 2014 per a search snippet only (page not opened) | – | Low |
| Babaganj (773), Farrukhabad (586), Saiyadraja (559), Sakaldiha (560) | Saroj, Vijay Singh, Manoj Singh, Sushil Singh | 2012 | 0: no dated evidence | – | – |
| Nautanwa (720) | Aman Mani Tripathi | 2017 | Supported: voted BJP in the Mar 2018 Rajya Sabha poll, called Yogi his "guardian" | https://www.tribuneindia.com/news/archive/nation/murder-accused-mla-calls-yogi-guardian-400271 | Medium–high |
| Kunda (775), Babaganj (773) | Raja Bhaiya, Saroj | 2017 | 0: ambiguous (JDL fought the BJP in 2019) | https://en.wikipedia.org/wiki/Jansatta_Dal_(Loktantrik) | Medium–low |

### Bihar

| AC (id) | MLA | Term | Coding | Source | Confidence |
|---|---|---|---|---|---|
| Balrampur (81) | Dulal Chandra Goswami | 2010 | Supported from Jun 2013; minister from May 2014 to the end of the term | https://en.wikipedia.org/wiki/Dulal_Chandra_Goswami | High |
| Lauriya (140) | Vinay Bihari | 2010 | Supported from Jun 2013; minister May 2014 – Jan 2015; 0 from Feb 2015 (sided with Manjhi) | https://www.dnaindia.com/lifestyle/report-jitan-ram-manjhi-sworn-in-asked-to-seek-trust-vote-on-may-23-1990110 | Medium |
| Dhaka (168), Obra (10) | Pawan Jaiswal, Somprakash Singh | 2010 | Supported Jun 2013 – Apr 2014 (trust vote of 19 Jun 2013); no evidence after | https://www.gulf-times.com/story/356700/nitish-is-confident-of-winning-trust-vote | High |
| Sikta (144), Dehri (181) | Dilip Varma, Jyoti Rashmi | 2010 | 0: voted against, 19 Jun 2013 | same | High |
| Bochaha (117), Kanti (119), Valmiki Nagar (145) | Baby Kumari, Ashok Choudhary, Rinku Singh | 2015 | Supported from Jul 2017 (trust vote of 28 Jul 2017; all 4 independents voted for, by inference) | https://www.indiatvnews.com/politics/national-nitish-govt-wins-confidence-vote-131-108-393698 | Medium |
| Mokama (156) | Anant Singh | 2015 | Supported Jul 2017 – Feb 2019; 0 from Mar 2019 (his wife ran for INC against JD(U)) | https://en.wikipedia.org/wiki/Anant_Kumar_Singh | Medium (end date approximate) |
| Chakai (73) | Sumit Kumar Singh | 2020 | Supported from Nov 2020; minister from 9 Feb 2021 | https://en.wikipedia.org/wiki/Seventh_Nitish_Kumar_ministry | High |

## Pre-poll alliances (`mla_alliance`, parties that won seats)

| Election | Alliances | Change from the November 8 list |
|---|---|---|
| Punjab 2012, 2017 | SAD+BJP; 2017 also AAP+LIP | confirmed |
| Punjab 2022 | SAD+BSP (BJP's partners PLC and SAD(S) won no seats) | confirmed |
| Haryana 2009, 2014 | INLD+SAD (HJC+BJP was not a pre-poll alliance in either) | confirmed |
| Haryana 2019 | none (SAD, allied with INLD, won no seats) | confirmed |
| Uttar Pradesh 2012 | INC+RLD; **Peace Party + Apna Dal** | **added** |
| Uttar Pradesh 2017 | NDA (BJP, ADS, SBSP); SP+INC | confirmed |
| Uttar Pradesh 2022 | NDA (BJP, ADS, NISHAD); SP+RLD+SBSP | confirmed |
| Bihar 2010 | NDA (JD(U), BJP); RJD+LJP | confirmed |
| Bihar 2015 | MGB (JD(U), RJD, INC); NDA (BJP, LJP, RLSP, HAM) | confirmed |
| Bihar 2020 | NDA (BJP, JD(U), VIP, HAM); MGB (RJD, INC, Left); GDSF (AIMIM, BSP) | **RLSP removed from GDSF** (won no seats; no value changes) |

Sources:
- https://en.wikipedia.org/wiki/2012_Punjab_Legislative_Assembly_election ; https://en.wikipedia.org/wiki/2017_Punjab_Legislative_Assembly_election ; https://en.wikipedia.org/wiki/2022_Punjab_Legislative_Assembly_election
- https://www.tribuneindia.com/2014/20140805/haryana.htm ; https://en.wikipedia.org/wiki/Haryana_Janhit_Congress_(BL)
- https://indiatvnews.com/politics/national/up-assembly-polls-three-state-level-parties-forge-alliance-3803.html (Peace Party, Apna Dal, Bundelkhand Congress)
- https://en.wikipedia.org/wiki/2017_Uttar_Pradesh_Legislative_Assembly_election ; https://www.tribuneindia.com/news/nation/uttar-pradesh-nda-alliance-takes-shape-bjp-nishad-party-and-apna-dal-to-contest-the-upcoming-assembly-elections-315639
- https://en.wikipedia.org/wiki/2010_Bihar_Legislative_Assembly_election ; https://en.wikipedia.org/wiki/2015_Bihar_Legislative_Assembly_election ; https://en.wikipedia.org/wiki/2020_Bihar_Legislative_Assembly_election

## Comparison with the team's earlier coalition file

The earlier file is `ac_election_coalition` (Dropbox `data_output/intermediate`, Oct 2026). It comes from `unique_id_coallition`, which was built from the hand-compiled sheet `Election-Dataset-Sheet1.pdf`.

Its `in_state_coalition` is fixed for each term. Against the start-of-term government above, it agrees in 2,376 of 2,535 AC-elections (94%). The differences:
- **Bihar 2010:** BJP coded 0 for the whole term, although it held ministries until June 2013.
- **Haryana 2009:** INLD coded 1 for 30 ACs, although it was the main opposition.
- **Smaller allies with ministers coded 0:** UP 2017 Apna Dal (S) and SBSP; UP 2022 Apna Dal (S) and NISHAD; Bihar 2020 VIP and HAM(S).
- **No changes within a term:** for example, Bihar in July 2017.

## Defections not followed

These MLAs keep the party they won with:
- **Haryana:**
  - Five HJC(BL) MLAs joined INC in Nov 2009; the merger was struck down in Oct 2014.
  - HJC(BL)'s 2014 MLAs joined INC in Apr 2016.
- **Uttar Pradesh:** in 2018, NISHAD's and RLD's single 2017 MLAs went over to the BJP.
- **Bihar:**
  - Three 2010 RJD MLAs became ministers in Jun 2014.
  - The 2020 BSP and LJP MLAs joined JD(U) in 2021.
  - VIP's three MLAs joined BJP in Mar 2022.
  - Four of AIMIM's five MLAs joined RJD in Jun 2022.
