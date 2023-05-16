# syntax=docker/dockerfile:1
#
# Copyright (C) 2022, Berachain Foundation. All rights reserved.
# See the file LICENSE for licensing terms.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

ARG GO_VERSION=1.20.4
ARG GOARCH=arm64
ARG GOOS=darwin

#######################################################
###       Stage 1 - Build Solidity Bindings         ###
#######################################################

# Use the latest foundry image
FROM ghcr.io/foundry-rs/foundry as foundry

WORKDIR /workdir

# Copy over all the solidity code.
ARG FOUNDRY_DIR
COPY ${FOUNDRY_DIR} ${FOUNDRY_DIR}
WORKDIR /workdir/${FOUNDRY_DIR}

RUN forge build --extra-output-files bin --extra-output-files abi

# #############################dock##########################
# ###         Stage 2 - Build the Application         ###
# #######################################################

FROM golang:${GO_VERSION}-alpine as builder

# Setup some alpine stuff that nobody really knows how or why it works.
# Like if ur reading this and u dunno just ask the devops guy or something.
RUN set -eux; \
    apk add git linux-headers ca-certificates build-base

# Copy our source code into the container
WORKDIR /workdir
COPY . .

# Copy the forge output
ARG FOUNDRY_DIR
COPY --from=foundry /workdir/${FOUNDRY_DIR}/out /workdir/${FOUNDRY_DIR}/out

# Build berad binary
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/go/pkg/mod \
    VERSION=$(echo $(git describe --tags) | sed 's/^v//') && \
    COMMIT=$(git log -1 --format='%H') && \
    env GOOS=${GOOS} GOARCH=${GOARCH} && \
    go build \
    -mod=readonly \
    -tags "netgo,ledger,muslc" \
    -ldflags "-X github.com/cosmos/cosmos-sdk/version.Name="polaris-cosmos" \
    -X github.com/cosmos/cosmos-sdk/version.AppName="polard" \
    -X github.com/cosmos/cosmos-sdk/version.Version=$VERSION \
    -X github.com/cosmos/cosmos-sdk/version.Commit=$COMMIT \
    -X github.com/cosmos/cosmos-sdk/version.BuildTags='netgo,ledger,muslc' \
    -X github.com/cosmos/cosmos-sdk/types.DBBackend="pebbledb" \
    -w -s -linkmode=external -extldflags '-Wl,-z,muldefs -static'" \
    -trimpath \
    -o /workdir/bin/ \
    ./cosmos/cmd/polard

#######################################################
###        Stage 3 - Prepare the Final Image        ###
#######################################################

FROM golang:${GO_VERSION}-alpine

# Copy over built executable into a fresh container.
COPY --from=builder /workdir/bin/polard /bin/