# Mend.io Security Demo - OWASP Dependency Track + Jenkins Integration

This repository contains a complete demonstration of integrating OWASP Dependency Track with Jenkins for automated vulnerability scanning and Software Bill of Materials (SBOM) management.

## Quick Start

1. **Prerequisites**
   - Docker and Docker Compose installed
   - At least 8GB RAM available
   - Ports 8080, 8081, 8082 available

2. **Clone and Start**
   ```bash
   git clone <this-repo-url>
   cd mend-security-demo
   make setup
   ```

3. **Access Services**
   - Jenkins: http://localhost:8080 (admin/admin)
   - Dependency Track: http://localhost:8081 (admin/admin)
   - Dependency Track Frontend: http://localhost:8082

4. **Run Demo**
   ```bash
   make demo
   ```

## Services Overview

- **Jenkins**: CI/CD orchestration and pipeline execution
- **OWASP Dependency Track**: Vulnerability management and SBOM analysis
- **PostgreSQL**: Database for Dependency Track
- **WebGoat**: Target application for vulnerability demonstration

## Architecture

```mermaid
%%{init: { "flowchart": { "htmlLabels": true } }}%%
flowchart TB
  subgraph "External Services"
    GH[<b>GitHub Repository</b><br/>WebGoat v8.1.0]
    NVD[<b>NIST NVD</b><br/>Vulnerability Database]
  end

  subgraph "Docker Environment"
    subgraph "Jenkins Container"
      J[Jenkins Server<br/>:8080]
      JP[Jenkins Pipeline Job]
      subgraph "Pipeline Stages"
        S1[<ul>
             <li>1. Clone WebGoat<br/>from GitHub</li>
           </ul>]
        S2[<ul>
             <li>2. Build Application<br/>with Maven</li>
           </ul>]
        S3[<ul>
             <li>3. Run Dependency Check<br/>Vulnerability Scan</li>
           </ul>]
        S4[<ul>
             <li>4. Generate CycloneDX<br/>SBOM</li>
           </ul>]
        S5[<ul>
             <li>5. Upload SBOM to<br/>Dependency Track</li>
           </ul>]
      end
    end

    subgraph "Dependency Track"
      DT_API[Dependency Track<br/>API Server<br/>:8081]
      DT_UI[Dependency Track<br/>Web Interface<br/>:8081]
      DT_DB[(Vulnerability<br/>Database)]
    end
  end

  subgraph "Generated Artifacts"
    DC_REPORT[Dependency Check<br/>HTML/XML Report]
    SBOM[CycloneDX SBOM<br/>JSON File]
    BUILD[WebGoat<br/>WAR File]
  end

  subgraph "Security Outputs"
    DASH[Security Dashboard<br/>&amp; Metrics]
    VULNS[Vulnerability<br/>Reports]
    ALERTS[Risk Alerts<br/>&amp; Notifications]
  end

  %% External connections
  GH -->|git clone| S1
  NVD -->|vulnerability data| S3
  NVD -->|vulnerability data| DT_API

  %% Jenkins pipeline flow
  J --> JP
  JP --> S1
  S1 --> S2
  S2 --> S3
  S3 --> S4
  S4 --> S5

  %% Artifact generation
  S2 --> BUILD
  S3 --> DC_REPORT
  S4 --> SBOM

  %% Dependency Track integration
  S5 -->|HTTP POST| DT_API
  SBOM -->|uploaded via API| DT_API
  DT_API --> DT_DB
  DT_API --> DT_UI

  %% Security outputs
  DT_UI --> DASH
  DT_DB --> VULNS
  DT_API --> ALERTS

  %% Styling
  classDef external fill:#e1f5fe
  classDef container fill:#f3e5f5
  classDef stage fill:#e8f5e8
  classDef artifact fill:#fff3e0
  classDef output fill:#ffebee

  class GH,NVD external
  class J,DT_API,DT_UI,DT_DB container
  class S1,S2,S3,S4,S5 stage
  class DC_REPORT,SBOM,BUILD artifact
  class DASH,VULNS,ALERTS output
```

For detailed setup instructions, see [docs/INSTALLATION.md](docs/INSTALLATION.md)