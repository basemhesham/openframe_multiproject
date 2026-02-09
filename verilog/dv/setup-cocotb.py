# SPDX-FileCopyrightText: 2023 Efabless Corporation

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#      http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# SPDX-License-Identifier: Apache-2.0
import click
import yaml
from pathlib import Path


@click.command()
@click.argument('caravel_root', type=click.Path(exists=True))
@click.argument('mcw_root', type=click.Path(exists=False))
@click.argument('pdk_root', type=click.Path(exists=True))
@click.argument('pdk')
@click.argument('user_project_root', type=click.Path(exists=True))
def update_design_info(caravel_root, mcw_root, pdk_root, pdk, user_project_root):
    # MCW is optional (e.g. openframe projects do not use mgmt_core_wrapper)
    mcw_value = mcw_root if (mcw_root and Path(mcw_root).exists()) else None
    data = {
        'CARAVEL_ROOT': caravel_root,
        'MCW_ROOT': mcw_value,
        'USER_PROJECT_ROOT': user_project_root,
        'PDK_ROOT': pdk_root,
        'PDK': pdk,
        'clk': 25,
        'caravan': False,
        'emailto': [None]
    }

    with open(f'{user_project_root}/verilog/dv/cocotb/design_info.yaml', 'w') as file:
        yaml.dump(data, file)


if __name__ == "__main__":
    update_design_info()
