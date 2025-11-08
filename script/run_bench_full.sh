#!/bin/bash
#
# Run DeepResearch inference on deepresearch_bench FULL dataset (100 queries)
# WARNING: This will take several hours and use significant API credits
#

set -e  # Exit on error

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEEPRESEARCH_ROOT="$SCRIPT_DIR/.."

echo "=========================================="
echo "DeepResearch Bench - FULL Dataset (100 queries)"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This will run 100 queries and may take 5-10 hours"
echo "⚠️  WARNING: This will use significant OpenRouter API credits"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted by user"
    exit 0
fi

echo ""

# Load environment variables
# 1. Load API keys from CubeScholar root
KEYS_FILE="/shared/data3/runchut2/proj/CubeScholar/.env.keys"
if [ ! -f "$KEYS_FILE" ]; then
    echo "Error: .env.keys file not found at $KEYS_FILE"
    echo "Please configure your API keys first"
    exit 1
fi

echo "Loading API keys from .env.keys..."
set -a
source "$KEYS_FILE"
set +a

# 2. Load DeepResearch configuration
ENV_FILE="$DEEPRESEARCH_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    echo "Please configure your environment first"
    exit 1
fi

echo "Loading DeepResearch configuration from .env..."
set -a
source "$ENV_FILE"
set +a

# Validate OpenRouter API key
if [ -z "$OPENROUTER_API_KEY" ]; then
    echo "Error: OPENROUTER_API_KEY not set in .env file"
    exit 1
fi

# Configuration
DATASET="$DEEPRESEARCH_ROOT/data/deepresearch_bench/bench_queries.jsonl"
OUTPUT_DIR="$DEEPRESEARCH_ROOT/output/deepresearch_bench_full"
MODEL_NAME="alibaba/tongyi-deepresearch-30b-a3b"
MAX_WORKERS=3  # Increased for full dataset
ROLLOUT_COUNT=1

echo "Configuration:"
echo "  Dataset:     $DATASET"
echo "  Output:      $OUTPUT_DIR"
echo "  Model:       $MODEL_NAME"
echo "  Workers:     $MAX_WORKERS"
echo "  Rollouts:    $ROLLOUT_COUNT"
echo ""

# Verify dataset exists
if [ ! -f "$DATASET" ]; then
    echo "Error: Dataset not found at $DATASET"
    echo "Please run convert_format.py first"
    exit 1
fi

echo "Starting inference..."
echo "Started at: $(date)"
echo ""

cd "$DEEPRESEARCH_ROOT"
python -u inference/run_multi_react.py \
  --dataset "$DATASET" \
  --output "$OUTPUT_DIR" \
  --model "$MODEL_NAME" \
  --max_workers $MAX_WORKERS \
  --roll_out_count $ROLLOUT_COUNT

echo ""
echo "=========================================="
echo "✓ Full dataset inference completed!"
echo "  Completed at: $(date)"
echo "  Results saved to: $OUTPUT_DIR"
echo "=========================================="
