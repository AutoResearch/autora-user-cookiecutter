"""
Basic Workflow
    Single condition Variable (0-1), Single Observation Variable(0-1)
    Theorist: LinearRegression
    Experimentalist: Random Sampling
    Runner: Firebase Runner (no prolific recruitment)
"""
import json

from autora.variable import VariableCollection, Variable
from autora.experimentalist.random import pool
from autora.experiment_runner.firebase_prolific import firebase_runner
from autora.state import StandardState, on_state, Delta

import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression

# *** Set up variables *** #
# independent variable is coherence (0 - 1)
# dependent variable is accuracy (0 - 1)
variables = VariableCollection(
    independent_variables=[Variable(name="coherence", allowed_values=np.linspace(0, 1, 101))],
    dependent_variables=[Variable(name="accuracy", value_range=(0, 1))])

# *** Set up the theorist *** #
# Here we use a linear regression as theorist, but you can use other theorists included in autora (for a list: https://autoresearch.github.io/autora/theorist/)
# Or you can set up your own theorist
theorist = LinearRegression()

# *** Set up the experimentalist *** #
# Here we use a random sampler as experimentalist, but you can use other experimentalists included in autora (for a list:  https://autoresearch.github.io/autora/experimentalist/)
# Or you can set up your own experimentalist
uniform_random_rng = np.random.default_rng(seed=180)

# *** Set up the runner *** #
# Here fill in your own credentials
# (https://console.firebase.google.com/)
#   -> project -> project settings -> service accounts -> generate new private key

firebase_credentials = {
    "type": "type",
    "project_id": "project_id",
    "private_key_id": "private_key_id",
    "private_key": "private_key",
    "client_email": "client_email",
    "client_id": "client_id",
    "auth_uri": "auth_uri",
    "token_uri": "token_uri",
    "auth_provider_x509_cert_url": "auth_provider_x509_cert_url",
    "client_x509_cert_url": "client_x509_cert_url"
}

# simple experiment runner that runs the experiment on firebase
experiment_runner = firebase_runner(
    firebase_credentials=firebase_credentials,
    time_out=100,
    sleep_time=5)

# *** Set up the state *** #
state = StandardState(
    variables=variables,
)


# Set up experimentalist on state
@on_state()
def experimentalist_on_state(variables):
    return Delta(conditions=pool(variables, num_samples=2))


# Set up runner on state
@on_state()
def runner_on_state(conditions):
    data = experiment_runner(conditions)
    # Here we need to parse what the list the experiment runner returns.
    result = []
    for item in data:
        parsed_item = json.loads(item)
        coherence = parsed_item['condition']['coherence']
        accuracy = parsed_item['observation']['accuracy']
        result.append({'coherence': coherence, 'accuracy': accuracy})

    return Delta(experiment_data=pd.DataFrame(result))


# Set up theorist on state
@on_state()
def theorist_on_state(experiment_data, variables):
    ivs = [iv.name for iv in variables.independent_variables]
    dvs = [dv.name for dv in variables.dependent_variables]
    x = experiment_data[ivs]
    y = experiment_data[dvs]
    return Delta(models=[theorist.fit(x, y)])


for _ in range(3):
    state = experimentalist_on_state(state)
    state = runner_on_state(state)
    state = theorist_on_state(state)


# *** Report the data *** #
# If you changed the theorist, also change this part
def report_linear_fit(m: LinearRegression, precision=4):
    s = f"y = {np.round(m.coef_[0].item(), precision)} x " \
        f"+ {np.round(m.intercept_.item(), 4)}"
    return s


print(report_linear_fit(state.models[0]))
print(report_linear_fit(state.models[-1]))