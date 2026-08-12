# Integrated Two-Device Incident Response Lab

An academic, portfolio-ready incident response project built on two authorized physical devices. Ubuntu acts as the analyst and server platform, while Windows 11 acts as the monitored endpoint.

**Student:** Ayham Al-Swaiti  
**Student ID:** 12116003  
**Course:** Special Topics in Information Security  
**Domain:** Incident Response

## 🎥 Project Demonstration

The complete project demonstration video is available in the final release:

[🎥 Watch / Download Project Demo][(https://github.com/alswaitiayham-byte/Integrated-Two-Device-Incident-Response-Lab/releases/tag/v1.0)]

## What this project demonstrates

* Remote endpoint visibility with Velociraptor.
* Linux audit collection and investigation with `auditd`.
* Log analysis and detection in Splunk.
* Timeline reconstruction in Timesketch.
* Windows memory acquisition with WinPmem and analysis with Volatility 3.
* Targeted containment, rollback, IOC handling, disk forensics, and recovery validation.
* Evidence integrity using SHA-256 manifests and verified transfers.

The workflow is:

```text
Prepare -> Detect -> Collect -> Contain -> Analyze -> Correlate -> Recover
```

## Lab design

|Role|Platform|Address|Main purpose|
|-|-|-:|-|
|Analyst and server|Ubuntu 26.04 LTS|`192.168.1.31`|Tool hosting, collection, analysis, and evidence storage|
|Monitored endpoint|Windows 11 Pro 25H2|`192.168.1.128`|Endpoint telemetry and memory acquisition|

The scenario is a labelled safe simulation. It does not use malware, exploitation, public scanning, or real attacker infrastructure. The addresses `198.51.100.77` and `203.0.113.50` come from the documentation ranges reserved by RFC 5737.

## Verified results

|Check|Result|
|-|-:|
|Velociraptor endpoint|Connected|
|Velociraptor process and network collection|336 rows|
|Simulated failed logins found in Splunk|12|
|Events imported into Timesketch|4,210|
|Events tagged `safe-simulation`|99|
|Windows memory image|About 11 GiB|
|Memory transfer SHA-256|Matching on Windows and Ubuntu|
|Volatility 3 plugin outputs|7 validated files|
|Safe containment and rollback|PASS|
|Disk recovery and backup validation|PASS|
|Final evidence package|PASS|

## Ten course skills

The exact skill names were verified at commit `2fb6a9faff42977f9e64b1f0dcb97bb2a1e67267`.

1. `implementing-velociraptor-for-ir-collection`
2. `analyzing-security-logs-with-splunk`
3. `analyzing-linux-audit-logs-for-intrusion`
4. `collecting-volatile-evidence-from-compromised-host`
5. `containing-active-breach`
6. `conducting-memory-forensics-with-volatility`
7. `performing-disk-forensics-investigation`
8. `collecting-indicators-of-compromise`
9. `building-incident-timeline-with-timesketch`
10. `validating-backup-integrity-for-recovery`

## Repository structure

```text
RUN\_ME\_FIRST.sh       Main command interface
scripts/              Setup, validation, and finalization
lab/                  Collection, analysis, forensics, and recovery logic
services/             Splunk and Timesketch container controls
windows/              Authorized Windows endpoint scripts
sample\_data/          Safe synthetic test data
docs/                 Safety, skill mapping, and implementation notes
```

## Quick start

Run only on systems you own or are authorized to test.

```bash
chmod +x RUN\_ME\_FIRST.sh
./RUN\_ME\_FIRST.sh setup
./RUN\_ME\_FIRST.sh status
```

After the Windows endpoint is enrolled:

```bash
./RUN\_ME\_FIRST.sh demo
./RUN\_ME\_FIRST.sh validate
./RUN\_ME\_FIRST.sh finalize
```

The complete command sequence and source listing are available in `Ayham\_IR\_All\_Code\_and\_Stages\_12116003.md`.

## Privacy and submission scope

Raw memory images, credentials, private keys, and generated Velociraptor client/server configuration files are intentionally excluded from the GitHub package. Screenshots and reported measurements come from the completed lab, while the included sample data remains synthetic and safe to review.

## Documentation

* `Ayham\_Integrated\_IR\_Final\_Report\_12116003.pdf` — academic and technical report.
* `Ayham\_IR\_All\_Code\_and\_Stages\_12116003.md` — simple stage guide plus complete code listing.
* `Ayham\_Incident\_Response\_Presentation\_Lecture\_Aligned\_12116003.pptx` — presentation deck.
* `Ayham\_IR\_Source\_Code\_12116003.zip` — privacy-safe source package.
* `SHA256SUMS.txt` — delivery file hashes.

## License and responsible use

This repository is provided for education and defensive security practice. Review the licenses of third-party tools before commercial use. Do not use the scripts against systems without explicit authorization.

