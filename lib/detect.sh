#!/usr/bin/env bash
# multirepo-space - Stack detection library
# Detects technology stack for a given repository path.
# Usage: source this file, then call detect_stack <repo_path>

detect_stack() {
  local repo_path="$1"
  local dir_name primary_tech framework stack_csv verify_cmds version

  dir_name=$(basename "$repo_path")

  primary_tech=""
  framework=""
  stack_csv=""
  verify_cmds=""

  local stack_parts=()

  # --- Primary detection ---

  # package.json
  if [[ -f "$repo_path/package.json" ]]; then
    local pkg
    pkg=$(cat "$repo_path/package.json")

    if echo "$pkg" | grep -q '"@angular/core"'; then
      version=$(echo "$pkg" | grep '"@angular/core"' | head -1 | sed 's/.*: *"[~^]*//' | sed 's/".*//' | cut -d. -f1)
      primary_tech="TypeScript"
      framework="Angular ${version}"
      verify_cmds="ng build, ng test, ng lint"
      stack_parts+=("Angular ${version}")
    elif echo "$pkg" | grep -q '"next"'; then
      primary_tech="TypeScript/JS"
      framework="Next.js"
      verify_cmds="npm run build, npm run lint"
      stack_parts+=("Next.js")
    elif echo "$pkg" | grep -q '"react"'; then
      primary_tech="TypeScript/JS"
      framework="React"
      verify_cmds="npm run build, npm test"
      stack_parts+=("React")
    elif echo "$pkg" | grep -q '"vue"'; then
      primary_tech="TypeScript/JS"
      framework="Vue.js"
      verify_cmds="npm run build, npm test"
      stack_parts+=("Vue.js")
    elif echo "$pkg" | grep -q '"svelte"'; then
      primary_tech="TypeScript/JS"
      framework="Svelte"
      verify_cmds="npm run build, npm run check"
      stack_parts+=("Svelte")
    elif echo "$pkg" | grep -q '"nuxt"'; then
      primary_tech="TypeScript/JS"
      framework="Nuxt"
      verify_cmds="npm run build, npm run lint"
      stack_parts+=("Nuxt")
    fi
  fi

  # pom.xml (Java/Spring Boot + Maven)
  if [[ -f "$repo_path/pom.xml" ]]; then
    local pom
    pom=$(cat "$repo_path/pom.xml")

    if echo "$pom" | grep -q 'spring-boot-starter'; then
      local sb_version
      sb_version=$(echo "$pom" | grep -A1 'spring-boot-starter-parent' | grep '<version>' | sed 's/.*<version>//' | sed 's/<.*//' | cut -d. -f1,2)
      local java_version
      java_version=$(echo "$pom" | grep '<java.version>' | sed 's/.*<java.version>//' | sed 's/<.*//')
      [[ -z "$java_version" ]] && java_version=$(echo "$pom" | grep '<maven.compiler.source>' | sed 's/.*<maven.compiler.source>//' | sed 's/<.*//')

      primary_tech="Java${java_version:+ $java_version}"
      framework="Spring Boot${sb_version:+ $sb_version} + Maven"
      verify_cmds="mvn compile, mvn test, mvn verify"
      stack_parts+=("Spring Boot${sb_version:+ $sb_version}")
      stack_parts+=("Maven")
      [[ -n "$java_version" ]] && stack_parts+=("Java $java_version")

      # Supplementary: JPA, Feign, databases
      echo "$pom" | grep -q 'spring-boot-starter-data-jpa' && stack_parts+=("JPA")
      echo "$pom" | grep -q 'spring-cloud-starter-openfeign' && stack_parts+=("Feign")
      echo "$pom" | grep -q 'postgresql' && stack_parts+=("PostgreSQL")
      echo "$pom" | grep -q 'mysql-connector' && stack_parts+=("MySQL")
      echo "$pom" | grep -q 'spring-boot-starter-data-mongodb' && stack_parts+=("MongoDB")
    fi
  fi

  # build.gradle / build.gradle.kts (Spring Boot + Gradle)
  if [[ -f "$repo_path/build.gradle" ]] || [[ -f "$repo_path/build.gradle.kts" ]]; then
    local gradle_file
    [[ -f "$repo_path/build.gradle.kts" ]] && gradle_file="$repo_path/build.gradle.kts" || gradle_file="$repo_path/build.gradle"
    local gradle
    gradle=$(cat "$gradle_file")

    if echo "$gradle" | grep -q 'org.springframework.boot'; then
      if [[ -z "$primary_tech" ]]; then
        if [[ "$gradle_file" == *".kts" ]]; then
          primary_tech="Kotlin"
        else
          primary_tech="Java/Kotlin"
        fi
        framework="Spring Boot + Gradle"
        verify_cmds="gradle build, gradle test"
        stack_parts+=("Spring Boot")
        stack_parts+=("Gradle")
      fi
    fi
  fi

  # Python: pyproject.toml takes precedence over requirements.txt
  if [[ -f "$repo_path/pyproject.toml" ]]; then
    local pyproj
    pyproj=$(cat "$repo_path/pyproject.toml")

    if echo "$pyproj" | grep -qi 'django'; then
      primary_tech="Python"
      framework="Django"
      verify_cmds="python manage.py test"
      stack_parts+=("Django")
    elif echo "$pyproj" | grep -qi 'fastapi'; then
      primary_tech="Python"
      framework="FastAPI"
      verify_cmds="pytest"
      stack_parts+=("FastAPI")
    elif echo "$pyproj" | grep -qi 'flask'; then
      primary_tech="Python"
      framework="Flask"
      verify_cmds="pytest"
      stack_parts+=("Flask")
    fi
  elif [[ -f "$repo_path/requirements.txt" ]]; then
    local reqs
    reqs=$(cat "$repo_path/requirements.txt")

    if echo "$reqs" | grep -qi 'django'; then
      primary_tech="Python"
      framework="Django"
      verify_cmds="python manage.py test"
      stack_parts+=("Django")
    elif echo "$reqs" | grep -qi 'fastapi'; then
      primary_tech="Python"
      framework="FastAPI"
      verify_cmds="pytest"
      stack_parts+=("FastAPI")
    elif echo "$reqs" | grep -qi 'flask'; then
      primary_tech="Python"
      framework="Flask"
      verify_cmds="pytest"
      stack_parts+=("Flask")
    fi
  fi

  # Go
  if [[ -f "$repo_path/go.mod" ]]; then
    if [[ -z "$primary_tech" ]]; then
      local go_version
      go_version=$(head -5 "$repo_path/go.mod" | grep '^go ' | awk '{print $2}')
      primary_tech="Go${go_version:+ $go_version}"
      framework=""
      verify_cmds="go build ./..., go test ./..."
      stack_parts+=("Go${go_version:+ $go_version}")
    fi
  fi

  # Rust
  if [[ -f "$repo_path/Cargo.toml" ]]; then
    if [[ -z "$primary_tech" ]]; then
      primary_tech="Rust"
      framework=""
      verify_cmds="cargo build, cargo test"
      stack_parts+=("Rust")
    fi
  fi

  # Dart / Flutter
  if [[ -f "$repo_path/pubspec.yaml" ]]; then
    if [[ -z "$primary_tech" ]]; then
      if grep -q 'flutter' "$repo_path/pubspec.yaml"; then
        primary_tech="Dart"
        framework="Flutter"
        verify_cmds="flutter analyze, flutter test"
        stack_parts+=("Flutter")
      else
        primary_tech="Dart"
        framework=""
        verify_cmds="dart analyze, dart test"
        stack_parts+=("Dart")
      fi
    fi
  fi

  # .NET (*.csproj)
  if compgen -G "$repo_path/*.csproj" > /dev/null 2>&1; then
    if [[ -z "$primary_tech" ]]; then
      primary_tech="C#"
      framework=".NET"
      verify_cmds="dotnet build, dotnet test"
      stack_parts+=(".NET")
    fi
  fi

  # --- Supplementary checks ---

  if [[ -f "$repo_path/tsconfig.json" ]]; then
    local has_ts=false
    for part in "${stack_parts[@]}"; do
      [[ "$part" == "TypeScript" ]] && has_ts=true
    done
    if ! $has_ts && [[ "$primary_tech" != "TypeScript" ]]; then
      stack_parts+=("TypeScript")
    fi
  fi

  [[ -f "$repo_path/angular.json" ]] && : # confirms Angular, already detected

  if compgen -G "$repo_path/src/**/*.scss" > /dev/null 2>&1 || compgen -G "$repo_path/src/*.scss" > /dev/null 2>&1; then
    stack_parts+=("SCSS")
  fi

  if compgen -G "$repo_path/tailwind.config.*" > /dev/null 2>&1; then
    stack_parts+=("Tailwind CSS")
  fi

  if [[ -f "$repo_path/package.json" ]]; then
    grep -q '"bootstrap"' "$repo_path/package.json" && stack_parts+=("Bootstrap")
    grep -q '"@angular/material"' "$repo_path/package.json" && stack_parts+=("Angular Material")
  fi

  if [[ -f "$repo_path/Dockerfile" ]]; then
    stack_parts+=("Docker")
  fi

  # --- Fallback ---
  if [[ -z "$primary_tech" ]]; then
    primary_tech="Generic"
    framework=""
    verify_cmds=""
  fi

  # --- Build outputs ---
  if [[ ${#stack_parts[@]} -gt 0 ]]; then
    stack_csv=$(IFS=', '; echo "${stack_parts[*]}")
  else
    stack_csv="$primary_tech"
  fi

  # Export results as global variables
  DETECT_PRIMARY_TECH="$primary_tech"
  DETECT_FRAMEWORK="$framework"
  DETECT_STACK_CSV="$stack_csv"
  DETECT_VERIFY_CMDS="$verify_cmds"
  DETECT_STACK_PARTS=("${stack_parts[@]}")
}

derive_alias() {
  local repo_path="$1"
  local alias_name
  alias_name=$(basename "$repo_path")
  alias_name=$(echo "$alias_name" | tr '_.' '-')
  alias_name=$(echo "$alias_name" | cut -c1-30)
  echo "$alias_name"
}
